import SwiftUI

struct TaskContextMenuPopover: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @Binding var isPresented: Bool
    /// `show()` 那一刻的快照。只当身份用（`id` 不会变），可变字段一律读 `task`。
    private let snapshot: Task
    let onCustomDate: () -> Void
    let onChooseParent: () -> Void
    @EnvironmentObject private var environment: AppEnvironment

    /// 菜单内容跟着工作区走，不是打开那一刻的快照。
    ///
    /// ⚠️ 这是「点完不收起」的前提：日期 / 优先级 / 清单 / 分组点完菜单要留着，
    /// 勾选和日期就必须**就地**更新。继续用快照的话，用户会看到
    /// 「我明明选了『工作』，勾还在『个人』上」——比直接收起菜单更糟。
    /// `workspace.task(for:)` 内部读 `revision`，所以工作区一变这里就重算。
    private var task: Task { workspace.task(for: snapshot.id) ?? snapshot }

    init(workspace: TaskWorkspaceModel, isPresented: Binding<Bool>,
         task: Task, onCustomDate: @escaping () -> Void,
         onChooseParent: @escaping () -> Void) {
        self.workspace = workspace
        self._isPresented = isPresented
        self.snapshot = task
        self.onCustomDate = onCustomDate
        self.onChooseParent = onChooseParent
    }

    private enum Submenu: Equatable { case list, tags, group }
    @State private var activeSubmenu: Submenu?
    /// 正在「排队」等意图延迟、还没展开的那个子菜单。用来判断"离开的是哪一行"，
    /// 避免 A 行的 `onHover(false)` 把 B 行刚排的队误杀。
    @State private var pendingSubmenu: Submenu?
    @State private var submenuHoverTimer: DispatchWorkItem?

    /// 第三级面板正在展示**哪个清单**的分组。只依附于 `.list` 子菜单——
    /// 「分组是清单里面的二级菜单」：清单是第一级，分组是第二级（合起来是菜单的第三层）。
    @State private var sectionHost: String?
    @State private var pendingSectionHost: String?
    @State private var sectionHoverTimer: DispatchWorkItem?

    /// 面板宽度对齐 Flutter TaskMenuMetrics.width = 220。
    ///
    /// ⚠️ 220 不是「看着顺眼」调出来的：日期行 5 个按钮、优先级行 4 个按钮
    /// 都是 `.frame(maxWidth: .infinity)` 自适应，**面板宽度实际上是被这两行
    /// 撑开的**——264 时它们分别占 247/248pt（99.6%）与 248/248pt（100%），
    /// 而文字行最长标签「添加子任务」后还空着 141.5pt（54%）。
    /// 收到 220 后两行按钮会自动收缩（46 → 37.6pt、59 → 48pt），
    /// 不需要改 `dateAction` / `priorityAction` 的布局。
    static let menuWidth: CGFloat = 220

    /// 悬浮多久后展开子菜单，对齐 Flutter WorkFollowMotion.submenuIntent（220ms）。
    private static let submenuIntent: TimeInterval = 0.22

    /// 菜单行的悬浮语义（对齐系统菜单，而不是"开一次就卡住"）：
    ///
    /// - **进入普通行** → 立即收起当前子菜单。
    /// - **进入带子菜单的行**，当前没有子菜单 → 等 `submenuIntent`（220ms）再展开，
    ///   免得鼠标扫过整张菜单时一路弹开。
    /// - **进入带子菜单的行**，已有子菜单在展 → **立即切换**（系统菜单就是这样；
    ///   切换不该再等 220ms）。
    /// - **离开某一行** → 只取消"这一行自己排的队"，不碰别人。
    ///
    /// ⚠️ 关键设计约束：**离开行 ≠ 收起子菜单**。子菜单在父面板右侧，鼠标必须能横穿
    /// 中间那段空隙走到子菜单里去；一离开行就收，子菜单就永远点不到。
    /// 所以「移开自动关闭」只对**进入另一行**生效 —— 这也正是系统菜单的做法。
    ///
    /// 旧实现是 `guard entering, activeSubmenu == nil`（照抄 Flutter 的
    /// `submenu != null` 守卫），后果是子菜单一旦展开就再也不切换、也不收起，
    /// 只能按 Esc 或点别处。这里改成上面的语义。
    private func hoverRow(_ submenu: Submenu?, entering: Bool) {
        guard entering else {
            if pendingSubmenu == submenu { cancelPendingSubmenu() }
            return
        }
        cancelPendingSubmenu()
        guard let submenu else {
            activeSubmenu = nil                     // 普通行：立即收起
            return
        }
        if activeSubmenu != nil {
            activeSubmenu = submenu                 // 已有子菜单在展：立即切换
            return
        }
        pendingSubmenu = submenu                    // 从无到有：走意图延迟
        let work = DispatchWorkItem {
            activeSubmenu = submenu
            pendingSubmenu = nil
            submenuHoverTimer = nil
        }
        submenuHoverTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.submenuIntent, execute: work)
    }

    private func cancelPendingSubmenu() {
        submenuHoverTimer?.cancel()
        submenuHoverTimer = nil
        pendingSubmenu = nil
    }

    /// 二级行（清单行）→ 三级面板（该清单的分组）的悬浮语义。
    ///
    /// 规则与 `hoverRow` **完全一致**（进入无子层的行立即收起、已有展开立即切换、
    /// 从无到有走意图延迟、离开行只取消自己排的队），所以理由写在上面那份注释里，
    /// 这里不重复。唯一要强调的是同一条约束：**离开清单行 ≠ 收起分组面板**，
    /// 分组面板在清单面板右侧，鼠标必须能横穿那段空隙走进去。
    private func hoverListRow(_ name: String?, entering: Bool) {
        guard entering else {
            if pendingSectionHost == name { cancelPendingSection() }
            return
        }
        cancelPendingSection()
        guard let name else {
            sectionHost = nil                      // 非清单行（搜索框）：立即收起
            return
        }
        if sectionHost != nil {
            sectionHost = name                     // 已有分组面板在展：立即切换
            return
        }
        pendingSectionHost = name
        let work = DispatchWorkItem {
            sectionHost = name
            pendingSectionHost = nil
            sectionHoverTimer = nil
        }
        sectionHoverTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.submenuIntent, execute: work)
    }

    private func cancelPendingSection() {
        sectionHoverTimer?.cancel()
        sectionHoverTimer = nil
        pendingSectionHost = nil
    }

    /// 收起三级面板。二级面板本身被换掉或收起时必须调，否则分组面板会留在屏幕上。
    private func clearSectionHost() {
        cancelPendingSection()
        sectionHost = nil
    }

    private func submenuBinding(for submenu: Submenu) -> Binding<Bool> {
        Binding(
            get: { activeSubmenu == submenu },
            set: { isPresented in
                if !isPresented, activeSubmenu == submenu {
                    activeSubmenu = nil
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("日期")
                .font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
                .padding(.horizontal, WFSpace.md)
                .padding(.top, WFSpace.md)
            HStack(spacing: WFSpace.xs) {
                dateAction("今天", symbol: "sun.max", offset: 0)
                dateAction("明天", symbol: "sunrise", offset: 1)
                dateAction("+7", symbol: "calendar", offset: 7)
                Button {
                    isPresented = false
                    onCustomDate()
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                        .frame(height: WFMetrics.controlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("选择日期")
                .accessibilityLabel("选择日期")
                Button {
                    apply { _ = workspace.clearDueDate(task.id) }
                } label: {
                    Image(systemName: "calendar.badge.minus")
                        .frame(maxWidth: .infinity)
                        .frame(height: WFMetrics.controlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(task.schedule.dueAt == nil)
                .help("清除日期")
                .accessibilityLabel("清除日期")
            }
            .foregroundStyle(WFColors.text)
            .padding(.horizontal, WFSpace.sm)
            if task.recurrence != .never {
                Button {
                    perform { workspace.skip(task.id) }
                } label: {
                    menuRow("跳过此周期", symbol: "forward.end")
                }
                .buttonStyle(.plain)
                .disabled(task.isClosed || RecurrenceEngine.next(for: task, now: workspace.clock(), calendar: workspace.calendar) == nil)
                .onHover { hoverRow(nil, entering: $0) }
            }

            Divider().padding(.vertical, WFSpace.xs)
            Text("优先级")
                .font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
                .padding(.horizontal, WFSpace.md)
            HStack(spacing: WFSpace.xs) {
                priorityAction(.high, color: WFColors.flagHigh)
                priorityAction(.medium, color: WFColors.flagMedium)
                priorityAction(.low, color: WFColors.accent)
                priorityAction(.none, color: WFColors.secondaryText)
            }
            .padding(.horizontal, WFSpace.sm)

            Divider().padding(.vertical, WFSpace.xs)
            VStack(spacing: 2) {
                // 放开嵌套（2026-10-17）：子任务右键同样可添加子任务（孙任务）。
                actionRow("添加子任务", symbol: "plus.square.on.square") {
                    perform { _ = workspace.requestChildTitleEditor(for: task.id) }
                }
                actionRow("关联主任务", symbol: "rectangle.3.group",
                          disabled: TaskParentPickerProjection.candidates(
                            for: task.id, tasks: workspace.allTasks, query: "").isEmpty) {
                    cancelPendingSubmenu()
                    activeSubmenu = nil
                    onChooseParent()
                }
                .accessibilityLabel("关联主任务")
                actionRow(task.isPinned ? "取消置顶" : "置顶", symbol: "pin") {
                    perform { _ = workspace.setPinned(task.id, !task.isPinned) }
                }
                actionRow(task.isAbandoned ? "重新开始" : "放弃",
                          symbol: task.isAbandoned ? "arrow.uturn.backward" : "xmark.circle",
                          disabled: task.status == .completed && !task.isAbandoned) {
                    perform {
                        if task.isAbandoned { _ = workspace.restore(task.id) }
                        else { _ = workspace.abandon(task.id) }
                    }
                }
                // 「分组」现在是「移动到清单」里的二级菜单（清单 → 分组），见下面的 `.list` 分支。
                //
                // ⚠️ 唯一例外是**子任务**：`moveToList` 不接受子任务
                // （`childListMoveNotSupported`，子任务跟着父任务换清单），所以「移动到清单」
                // 对它不出现，分组也就无从进入。这里为子任务保留一个顶层入口，
                // 免得「给子任务换分组」这个能力静默消失。
                //
                // 造型沿革：这一行早先是个裸 `Menu`，在 `VStack` 里 SwiftUI 不把它当菜单项，
                // 而是画成**下拉按钮**（灰色胶囊、⌄、居中、没有图标列、行高不走 `menuRow`），
                // 成了整张菜单里唯一不按菜单行造型画的一行。现在统一走 `menuRow`。
                if task.parentID != nil, task.list.name != TaskList.inbox.name {
                    Button { activeSubmenu = .group } label: {
                        menuRow("移动到分组", symbol: "rectangle.3.group", trailing: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .background(activeSubmenu == .group ? WFColors.selection : .clear,
                                in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                    .onHover { hoverRow(.group, entering: $0) }
                    .background(AnchoredPropertyPanel(
                        isPresented: submenuBinding(for: .group),
                        width: 196, placement: .submenu
                    ) {
                        TaskContextSectionPicker(workspace: workspace, listName: task.list.name,
                            selected: task.sectionID,
                            onCancel: { activeSubmenu = nil },
                            onSelect: { sectionID in
                                // 与「移动到清单 → 分组」同一口径：点完不收，勾选就地更新。
                                apply { _ = workspace.setTaskSection(task.id, sectionID: sectionID) }
                            })
                    })
                }
                if task.parentID == nil {
                    Button { activeSubmenu = .list } label: {
                        menuRow("移动到", symbol: "tray.full", trailing: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .disabled(!workspace.canMoveToList(task.id))
                    // Flutter：子菜单挂到行右侧（gap 14），展开期间行保持选中底色。
                    .background(activeSubmenu == .list ? WFColors.selection : .clear,
                                in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                    .onHover { hoverRow(.list, entering: $0) }
                    .background(AnchoredPropertyPanel(
                        isPresented: submenuBinding(for: .list),
                        width: 196, placement: .submenu
                    ) {
                        // 「分组是清单里面的二级菜单」：清单行再往右展开第三级面板，
                        // 列出**那个清单**的分组。选分组 = 换清单 + 落分组，一次提交。
                        TaskContextListPicker(
                            workspace: workspace,
                            selected: task.list.name,
                            currentSectionID: task.sectionID,
                            sectionHost: $sectionHost,
                            onHoverRow: { hoverListRow($0, entering: $1) },
                            onPick: { name, sectionID in
                                // 点完**不收**：清单面板和分组面板都留着，勾选就地更新，
                                // 用户可以接着换一个清单或分组。收尾交给 Esc / 点菜单外。
                                // 顺手把三级面板钉到刚点的这个清单上，免得它显示上一个清单的分组。
                                sectionHost = name
                                let target = TaskList(name: name)
                                // 没变就不提交：`commit` 每次都压一份撤销快照，
                                // 空操作会白吃掉用户一次 ⌘Z。
                                guard target.name != task.list.name
                                        || sectionID != task.sectionID else { return }
                                apply { _ = workspace.moveToList(task.id, target, sectionID: sectionID) }
                            },
                            onCancel: { activeSubmenu = nil })
                    })
                }
                Button { activeSubmenu = .tags } label: {
                    menuRow("标签", symbol: "tag", trailing: "chevron.right")
                }
                .buttonStyle(.plain)
                .background(activeSubmenu == .tags ? WFColors.selection : .clear,
                            in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .onHover { hoverRow(.tags, entering: $0) }
                // 标签子菜单**不跟着收窄**，仍是 264（= `TaskTagPickerPopover`
                // 自身宽度）。它是跨页面复用的组件（快速添加 / 批量面板 / 详情页），
                // 改它要同时动 5 个调用点和 2 个测试。代价是悬浮时会看到
                // 「父 220 → 子 264」变宽的一跳，与「移动到分组/清单」的 196 不同步。
                .background(AnchoredPropertyPanel(
                    isPresented: submenuBinding(for: .tags),
                    width: 264, placement: .submenu
                ) {
                    TaskTagPickerPopover(initialTags: task.tags, workspace: workspace,
                        onCancel: { activeSubmenu = nil },
                        onApply: { tags in
                            activeSubmenu = nil
                            perform { workspace.setTags(task.id, tags) }
                        })
                })
                actionRow("开始专注", symbol: "timer") {
                    perform { environment.startFocus(for: task.id) }
                }
                actionRow("创建副本", symbol: "doc.on.doc") {
                    perform { workspace.duplicate(task.id) }
                }
                actionRow("复制链接", symbol: "link") {
                    perform {
                        let copied = TaskLinkClipboard.copy(task)
                        environment.feedback.show(FeedbackEvent(kind: copied ? .success : .error,
                            message: copied ? "已复制任务链接" : "无法复制任务链接"))
                    }
                }
                actionRow("打开便签", symbol: "note") {
                    perform { StickyNoteWindowController.shared.open(taskID: task.id) }
                }
            }

            Divider().padding(.vertical, WFSpace.xs)
            actionRow("转换为笔记", symbol: "doc.text") {
                perform { _ = environment.convertTaskToNote(task.id) }
            }
            actionRow("删除", symbol: "trash", destructive: true) {
                perform { _ = workspace.delete(task.id) }
            }
        }
        .padding(.vertical, WFSpace.xs)
        .frame(width: Self.menuWidth)
        .onExitCommand { isPresented = false }
        // 二级面板不是 `.list` 时三级面板必须跟着收掉，否则切到「标签」后
        // 分组面板会孤零零留在屏幕上（它是独立 NSPanel，不会随二级面板自动消失）。
        .onChange(of: activeSubmenu) { _, newValue in
            if newValue != .list { clearSectionHost() }
        }
        .onDisappear {
            cancelPendingSubmenu()
            clearSectionHost()
        }
    }

    private func dateAction(_ title: String, symbol: String, offset: Int) -> some View {
        Button {
            apply { _ = workspace.moveDueDate(task.id, to: workspace.dateFromToday(offset)) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title).font(.system(size: 11))
            }
            .frame(maxWidth: .infinity)
            .frame(height: WFMetrics.controlHeight + 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(offset == 7 ? "安排到 7 天后" : title)
    }

    private func priorityAction(_ priority: TaskPriority, color: Color) -> some View {
        Button {
            apply { _ = workspace.setPriority(task.id, priority) }
        } label: {
            Image(systemName: priority == .none ? "flag" : "flag.fill")
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: WFMetrics.controlHeight)
                .background(task.priority == priority ? WFColors.selection : .clear,
                            in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(priorityTitle(priority))
        .accessibilityLabel(priorityTitle(priority))
    }

    private func actionRow(_ title: String, symbol: String,
                           trailing: String? = nil, disabled: Bool = false,
                           destructive: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            menuRow(title, symbol: symbol, trailing: trailing, destructive: destructive)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        // 普通行：鼠标落到这里就收掉正展开的子菜单（"移开自动关闭"）。
        .onHover { hoverRow(nil, entering: $0) }
    }

    private func menuRow(_ title: String, symbol: String,
                         trailing: String? = nil, destructive: Bool = false) -> some View {
        HStack(spacing: WFSpace.md) {
            Image(systemName: symbol)
                .frame(width: WFMetrics.icon)
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Image(systemName: trailing).font(.caption).foregroundStyle(WFColors.secondaryText)
            }
        }
        .font(WFType.body)
        .foregroundStyle(destructive ? Color.red : WFColors.text)
        .padding(.horizontal, WFSpace.md)
        .frame(height: WFMetrics.controlHeight)
        .contentShape(Rectangle())
        .modifier(MenuRowHoverHighlight())
    }

    /// 文案统一取领域类型的 `title`，不再在这里维护第二份表。
    private func priorityTitle(_ priority: TaskPriority) -> String { priority.title }

    /// 一次性命令 / 会打开别的窗口 / 不可逆 —— 点完收起整张菜单。
    private func perform(_ action: () -> Void) {
        isPresented = false
        action()
    }

    /// 「可反复改的属性」（日期 / 优先级 / 清单 / 分组）—— **点完不收菜单**。
    ///
    /// 收起的代价：想改主意（换成另一个清单、再换个分组、改完日期再调优先级）
    /// 就得重新右键一次，而菜单本来就在手边、鼠标也还在上面。
    /// 留着之后勾选/日期就地更新（靠 `task` 走工作区），
    /// 用户按 Esc 或点菜单外来收尾 —— 这也正是系统菜单的习惯。
    ///
    /// ⚠️ 别把「一次性的」混进来：「跳过此周期」虽然是日期动作，但它是一次性命令，
    /// 点完要收；「自定义日期」「打开便签」「添加子任务」会开别的窗口，也要收。
    private func apply(_ action: () -> Void) {
        action()
    }
}

/// 菜单行的悬浮底色（对齐 Flutter 菜单 InkWell 的 hover overlay）。
private struct MenuRowHoverHighlight: ViewModifier {
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background(hovered ? WFColors.hover : .clear,
                        in: RoundedRectangle(cornerRadius: WFMetrics.corner))
            .onHover { hovered = $0 }
    }
}

/// 「移动到清单」的二级面板。每个清单行右边带箭头，悬停时在**这一行**右侧再展开
/// 第三级面板（`TaskContextSectionPicker`），列出该清单的分组——这就是
/// 「分组是清单里面的二级菜单」。
///
/// ⚠️ 第三级的展开/切换/收起**不在这里决定**：`sectionHost` 与 `onHoverRow` 都由
/// `TaskContextMenuPopover` 持有，因为一级→二级和二级→三级必须共用同一套悬浮语义。
/// 尤其"离开行不收起"那条：第三级在第二级右侧，鼠标得横穿中间的空隙走进去，
/// 一旦按"离开就收"写，第三级就永远点不到。
private struct TaskContextListPicker: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    /// 任务当前所在清单（打勾用）。
    let selected: String
    /// 任务当前所在分组；只在悬停的清单**就是** `selected` 时才打勾 / 给「移出分组」。
    let currentSectionID: String?
    /// 第三级面板正在展示哪个清单的分组。
    @Binding var sectionHost: String?
    /// 清单行的悬浮进出：`(清单名, 是否进入)`；清单名 `nil` = 非清单行（搜索框）。
    let onHoverRow: (String?, Bool) -> Void
    /// 选中「清单 + 分组」。分组 `nil` = 只要清单不落分组（点清单行本身就是这条）。
    let onPick: (String, String?) -> Void
    let onCancel: () -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var matches: [String] {
        workspace.availableListNames.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(WFColors.secondaryText)
                TextField("搜索清单", text: $query).textFieldStyle(.plain).focused($searchFocused)
            }
            .padding(WFSpace.md)
            // 搜索框不是子层行：鼠标挪上来就把第三级收掉。
            .onHover { onHoverRow(nil, $0) }
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(matches, id: \.self) { name in
                        listRow(name)
                    }
                    if matches.isEmpty {
                        Text("没有匹配的清单").font(WFType.supporting)
                            .foregroundStyle(WFColors.secondaryText).padding(WFSpace.lg)
                    }
                }
            }
        }
        // 宽度对齐 Flutter TaskEditorMetrics.listPopoverWidth = 196。
        .frame(width: 196, height: 300)
        .onAppear { searchFocused = true }
        .onExitCommand(perform: onCancel)
    }

    private func listRow(_ name: String) -> some View {
        let sections = workspace.listSections(forList: name)
        // 收集箱不给分组入口（与旧「移动到分组」只在非收集箱出现的口径一致）。
        // 其余清单**一律**给入口，哪怕现在一个分组都没有——否则「添加分组…」
        // 在还没有分组的清单里永远点不到，等于把新建分组的能力锁死了。
        let offersSections = name != TaskList.inbox.name || !sections.isEmpty
        return Button { onPick(name, nil) } label: {
            HStack(spacing: WFSpace.md) {
                Image(systemName: name == TaskList.inbox.name ? "tray" : "list.bullet")
                    .foregroundStyle(WFColors.secondaryText)
                Text(name).frame(maxWidth: .infinity, alignment: .leading)
                if name == selected {
                    Image(systemName: "checkmark").foregroundStyle(WFColors.accent)
                }
                if offersSections {
                    Image(systemName: "chevron.right").font(.caption)
                        .foregroundStyle(WFColors.secondaryText)
                }
            }
            .padding(.horizontal, WFSpace.md)
            .frame(height: WFMetrics.controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { onHoverRow(name, $0) }
        // 第三级锚在**这一行**上（`.submenu` 的语义就是"挂到锚点行右侧"）。
        .background(AnchoredPropertyPanel(
            isPresented: offersSections ? sectionBinding(for: name) : .constant(false),
            width: 196, placement: .submenu
        ) {
            TaskContextSectionPicker(
                workspace: workspace,
                listName: name,
                selected: name == selected ? currentSectionID : nil,
                onCancel: { sectionHost = nil },
                onSelect: { sectionID in
                    // 选完分组也不收：面板留着，勾选就地跳到新分组（`onPick` 会把
                    // `sectionHost` 钉回这个清单）。要收就按 Esc 或点菜单外。
                    onPick(name, sectionID)
                })
        })
    }

    private func sectionBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: { sectionHost == name },
            set: { isPresented in
                if !isPresented, sectionHost == name { sectionHost = nil }
            }
        )
    }
}

/// 三级面板：**某个清单**的分组。由 `TaskContextListPicker` 的清单行悬停展开；
/// 子任务那条顶层「移动到分组」也用它（那时 `listName` = 任务自己所在的清单）。
///
/// 行造型与 `TaskContextListPicker` 同源（同宽、同行高、图标列 + 右侧勾选）。
/// 原来裸 `Menu` 里的「添加分组…」「移出分组」也一并搬到这里，否则会退回系统菜单造型
/// （灰色胶囊下拉按钮），问题原样复现。
private struct TaskContextSectionPicker: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let listName: String
    let selected: String?
    let onCancel: () -> Void
    let onSelect: (String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // 「移出分组」只在真的在某个分组里时才给——否则是一个点了没变化的死行。
                if selected != nil {
                    row("移出分组", symbol: "minus.circle", checked: false) { onSelect(nil) }
                }
                ForEach(workspace.listSections(forList: listName)) { section in
                    row(section.title, symbol: "rectangle.3.group",
                        checked: section.id == selected) { onSelect(section.id) }
                }
                if workspace.listSections(forList: listName).isEmpty {
                    Text("这个清单还没有分组").font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, WFSpace.md)
                        .padding(.vertical, WFSpace.lg)
                }
            }
            .padding(.vertical, WFSpace.xs)
            Divider()
            Button(action: addSection) {
                HStack(spacing: WFSpace.md) {
                    Image(systemName: "plus")
                        .frame(width: WFMetrics.icon)
                        .foregroundStyle(WFColors.secondaryText)
                    Text("添加分组…").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(WFType.body)
                .foregroundStyle(WFColors.text)
                .padding(.horizontal, WFSpace.md)
                .frame(height: WFMetrics.controlHeight)
                .contentShape(Rectangle())
                .modifier(MenuRowHoverHighlight())
            }
            .buttonStyle(.plain)
            .padding(.vertical, WFSpace.xs)
        }
        .frame(width: 196)
        .onExitCommand(perform: onCancel)
    }

    private func row(_ title: String, symbol: String, checked: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: WFSpace.md) {
                Image(systemName: symbol).foregroundStyle(WFColors.secondaryText)
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
                if checked { Image(systemName: "checkmark").foregroundStyle(WFColors.accent) }
            }
            .font(WFType.body)
            .foregroundStyle(WFColors.text)
            .padding(.horizontal, WFSpace.md)
            .frame(height: WFMetrics.controlHeight)
            .contentShape(Rectangle())
            .modifier(MenuRowHoverHighlight())
        }
        .buttonStyle(.plain)
    }

    /// 新建分组后直接落进新分组——与原 `Menu` 里的行为一致（省掉「建完再点一次」）。
    private func addSection() {
        guard let title = TaskNamePrompt.ask("添加分组"),
              workspace.addListSection(listName, title: title),
              let section = workspace.listSections(forList: listName)
                .first(where: { $0.title == title })
        else { return }
        onSelect(section.id)
    }
}
