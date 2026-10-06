import SwiftUI

struct IconRailView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    let onNavigate: (NativeDestination) -> Void
    let onOpenQuickOpen: () -> Void
    @Environment(\.openSettings) private var openSettings
    @Environment(\.mainWindowRailInset) private var mainWindowRailInset

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
            // ⚠️ SF Symbols 的实心覆盖是**部分**的，下面 6 个是换过的（隐喻有变）：
            //   · 笔记  text.alignleft → text.document.fill（描边线条没有实心版）
            //   · 日历  calendar       → calendar.circle.fill（**唯一的实心日历**，形状变圆）
            //   · 倒数  hourglass      → hourglass.bottomhalf.filled（保留沙漏，做成半实心）
            //   · 专注  timer          → timer.circle.fill（保留秒表，外面加实心圆）
            //   · 习惯  checkmark.seal → star.square.fill（滴答的习惯就是这个形）
            //   · 摘要  square.and.pencil → list.bullet.clipboard.fill
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
railButton(.summary, symbol: "list.bullet.clipboard.fill", title: "摘要",
                       selected: navigation.destination == .summary)
            Spacer()
            Button(action: onOpenQuickOpen) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: RailMetrics.iconSize))
                    .frame(width: RailMetrics.hitSize, height: RailMetrics.hitSize)
            }.help("快速打开（⌘K）").accessibilityLabel("快速打开")
            Button { openSettings() } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: RailMetrics.iconSize))
                    .frame(width: RailMetrics.hitSize, height: RailMetrics.hitSize)
            }.help("设置（⌘,）").accessibilityLabel("设置")
        }
        .buttonStyle(.plain)
        .foregroundStyle(WFColors.secondaryText)
        .padding(.top, max(RailMetrics.topPadding, mainWindowRailInset))
        .padding(.bottom, RailMetrics.topPadding)
        .frame(width: RailMetrics.width)
        .background(WFColors.canvas)
        .focusRenderAnchor(.rail)
    }

    private func railButton(_ destination: NativeDestination, symbol: String,
                            title: String, selected: Bool) -> some View {
        Button { onNavigate(destination) } label: {
            Image(systemName: symbol)
                .font(.system(size: RailMetrics.iconSize))
                .foregroundStyle(selected ? WFColors.accent : WFColors.secondaryText)
                .frame(width: RailMetrics.hitSize, height: RailMetrics.hitSize)
                .focusRenderAnchor(.railSelectedHitArea)
        }.help(title).accessibilityLabel(title)
    }
}

/// 对齐滴答清单的侧栏：智能清单（右侧灰计数）→ 中段清单/过滤器/标签 →
/// 底部固定"已完成 / 垃圾桶"，行高 32 的紧凑密度。
struct NavigationColumnView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    @EnvironmentObject private var environment: AppEnvironment
    /// Seam for the saved-filter group (Wave 1 F5): the shell passes the
    /// module's FilterStore here; when nil the section stays hidden.
    var filterStore: FilterStore? = nil
    var onNavigate: () -> Void = {}

    /// 智能清单顺序对齐滴答：所有 → 最近 7 天 → 今天 → 明天 → 收集箱。
    private let smartLists: [NativeDestination] = [.allTasks, .nextSevenDays, .today, .tomorrow, .inbox]
    private let bottomLists: [NativeDestination] = [.completed, .trash]

    private var destinations: [NativeDestination] {
        if navigation.destination.isNotes { return [.notes, .notesTrash] }
        if navigation.destination == .calendar { return [.calendar] }
        if navigation.destination == .matrix { return [.matrix] }
        if navigation.destination == .countdown { return [.countdown] }
        if navigation.destination == .focus { return [.focus] }
        if navigation.destination == .habits { return [.habits] }
        if navigation.destination == .summary { return [.summary] }
        return NativeDestination.taskDestinations
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if navigation.destination.isTaskList {
                ForEach(visibleSmartLists) { destination in
                    if SmartListVisibility.isConfigurable(destination) {
                        destinationRow(destination)
                            .contextMenu { visibilityMenu(for: destination) }
                    } else {
                        destinationRow(destination)
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TaskCollectionsView(workspace: workspace, navigation: navigation, onNavigate: onNavigate)
                        if let filterStore {
                            TaskFiltersSectionView(workspace: workspace, filterStore: filterStore,
                                                   navigation: navigation, onNavigate: onNavigate)
                        }
                        TaskTagsSectionView(workspace: workspace, navigation: navigation, onNavigate: onNavigate)
                    }
                }
                Divider().padding(.vertical, WFSpace.xs)
                ForEach(bottomLists) { destinationRow($0) }
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
        Picker("显示状态", selection: Binding(
            get: { environment.viewPreferences.visibility(for: destination) },
            set: { environment.viewPreferences.setVisibility($0, for: destination) })) {
            ForEach(SmartListVisibility.allCases) { state in
                Text(state.title).tag(state)
            }
        }
        .pickerStyle(.inline)
    }

    private func destinationRow(_ destination: NativeDestination) -> some View {
        Button {
            environment.navigate(to: destination)
            onNavigate()
        } label: {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: destination.symbol)
                    .font(.system(size: 14))
                    .frame(width: 18)
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
            .padding(.horizontal, WFSpace.sm)
            .frame(height: NavigationMetrics.rowHeight)
            .background(navigation.destination == destination
                        ? WFColors.listSelection : .clear,
                        in: RoundedRectangle(cornerRadius: WFMetrics.corner))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.title)
    }
}

private struct NotesNavigationSection: View {
    @ObservedObject var notes: NotesWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    @EnvironmentObject private var environment: AppEnvironment
    var onNavigate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("全部笔记", symbol: "text.alignleft", folder: nil)
            row("收藏", symbol: "star", folder: nil, favorites: true)
            row("未归档", symbol: "folder", folder: "未归档")
            HStack {
                Text("文件夹").font(WFType.supporting)
                Spacer()
                Button {
                    if let name = TaskNamePrompt.ask("新建文件夹") {
                        if notes.addFolder(name) { notes.folderFilter = name; notes.favoritesOnly = false; environment.navigate(to: .notes) }
                        else { TaskNamePrompt.invalidName() }
                    }
                } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("新建文件夹")
            }.foregroundStyle(WFColors.secondaryText)
             .padding(.horizontal, WFSpace.sm).padding(.top, WFSpace.lg).padding(.bottom, WFSpace.sm)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(notes.folders, id: \.self) { folder in
                        row(folder, symbol: "folder", folder: folder)
                            .contextMenu {
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
            .background(selected ? WFColors.listSelection : .clear, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// Saved-filter group (Wave 1 F5) shown under the task collections. Rendered
/// only when the shell wires a FilterStore through `NavigationColumnView.filterStore`.
/// Clicking an entry navigates to 所有任务 and activates it; clicking the active
/// entry again cancels the filter. Editing/deleting lives in the row's context menu.
private struct TaskFiltersSectionView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var filterStore: FilterStore
    @ObservedObject var navigation: AppNavigation
    var onNavigate: () -> Void = {}
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showEditor = false
    @State private var editingFilter: SavedFilter?

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.xs) {
            sectionHeader("过滤器")
            ForEach(filterStore.filters) { filter in
                filterRow(filter)
            }
            Button {
                editingFilter = nil
                showEditor = true
            } label: {
                HStack(spacing: WFSpace.sm) {
                    Image(systemName: "plus").font(.system(size: 13))
                    Text("新建过滤器").lineLimit(1)
                }
                .foregroundStyle(WFColors.secondaryText)
                .padding(.horizontal, WFSpace.sm)
                .frame(height: NavigationMetrics.rowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .help("新建过滤器")
        }
        .buttonStyle(.plain)
        .font(WFType.navigation)
        .sheet(isPresented: $showEditor) {
            FilterEditorView(store: filterStore, workspace: workspace,
                             initial: editingFilter) { showEditor = false }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(WFType.supporting)
            .foregroundStyle(WFColors.secondaryText)
            .padding(.horizontal, WFSpace.sm)
            .padding(.top, WFSpace.lg)
            .padding(.bottom, WFSpace.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            HStack(spacing: WFSpace.sm) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(filter.name).lineLimit(1)
                Spacer(minLength: WFSpace.xs)
            }
            .foregroundStyle(WFColors.text)
            .padding(.horizontal, WFSpace.sm)
            .frame(height: NavigationMetrics.rowHeight)
            .background(selected ? WFColors.listSelection : .clear,
                        in: RoundedRectangle(cornerRadius: WFMetrics.corner))
            .contentShape(Rectangle())
        }
        .contextMenu {
            Button("编辑") {
                editingFilter = filter
                showEditor = true
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
