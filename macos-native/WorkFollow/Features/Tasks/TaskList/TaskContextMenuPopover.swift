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

    private enum Submenu: Equatable { case list, tags, group, focus, focusEstimate }
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
    @StateObject private var menuController = BusinessMenuController()

    /// 主卡与清单子菜单共用标准宽度，日期与优先级各有四个等宽入口。
    static let menuWidth = PopupMetrics.menuWidth

    /// 悬浮多久后展开子菜单，对齐 Flutter WorkFollowMotion.submenuIntent（220ms）。
    private static let submenuIntent = PopupMetrics.submenuIntent

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
            guard pendingSubmenu == submenu else { return }
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
            guard pendingSectionHost == name else { return }
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

    private func openSectionMenu(_ name: String) {
        cancelPendingSection()
        sectionHost = name
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
            HStack(spacing: 12) {
                dateAction("今天", symbol: "sun.max", offset: 0)
                dateAction("明天", symbol: "sunrise", offset: 1)
                dateAction("+7", symbol: "calendar", offset: 7)
                Button {
                    isPresented = false
                    onCustomDate()
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 19))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("选择日期")
                .accessibilityLabel("选择日期")
                .taskContextMenuAnchor(.customDate)
                // 第五个快选钮「清除日期」：Flutter `clearDate` / 滴答日期行第 5 钮。
                // 图标对齐 Flutter 的 event_busy（带斜杠的日历）；没有日期就禁用。
                Button {
                    apply { _ = workspace.clearDueDate(task.id) }
                } label: {
                    Image(systemName: "calendar.badge.xmark")
                        .font(.system(size: 19))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(task.schedule.dueAt == nil)
                .foregroundStyle(WFColors.text)
                .help("清除日期")
                .accessibilityLabel("清除日期")
                .taskContextMenuAnchor(.clearDate)
            }
            .foregroundStyle(WFColors.text)
            .padding(.horizontal, WFSpace.sm)
            .padding(.vertical, 12)
            if task.recurrence != .never {
                Button {
                    perform { workspace.skip(task.id) }
                } label: {
                    menuRow("跳过此周期", symbol: "forward.end")
                        .padding(.horizontal, 16).frame(height: 34)
                }
                .buttonStyle(.plain)
                .disabled(task.isClosed || RecurrenceEngine.next(for: task, now: workspace.clock(), calendar: workspace.calendar) == nil)
                .onHover { hoverRow(nil, entering: $0) }
            }

            Text("优先级")
                .font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
                .padding(.horizontal, WFSpace.md)
                .padding(.top, 4)
            HStack(spacing: 26) {
                priorityAction(.high, color: WFColors.flagHigh)
                priorityAction(.medium, color: WFColors.flagMedium)
                priorityAction(.low, color: WFColors.accent)
                priorityAction(.none, color: WFColors.secondaryText)
            }
            .padding(.horizontal, WFSpace.sm)
            .padding(.vertical, 12)

            Divider().padding(.top, WFSpace.xs)
            BusinessMenuContent(controller: menuController, close: { isPresented = false },
                dismissAll: {}, maximumHeight: nil) {
            VStack(spacing: 0) {
                // 放开嵌套（2026-10-17）：子任务右键同样可添加子任务（孙任务）。
                actionRow("添加子任务", symbol: "task.subtask") {
                    perform { _ = workspace.requestChildTitleEditor(for: task.id) }
                }
                actionRow("关联主任务", symbol: "task.parent",
                          disabled: TaskParentPickerProjection.candidates(
                            for: task.id, tasks: workspace.allTasks, query: "").isEmpty) {
                    cancelPendingSubmenu()
                    activeSubmenu = nil
                    onChooseParent()
                }
                .accessibilityLabel("关联主任务")
                actionRow(task.isPinned ? "取消置顶" : "置顶", symbol: "task.pin") {
                    perform { _ = workspace.setPinned(task.id, !task.isPinned) }
                }
                actionRow(task.isAbandoned ? "重新开始" : "放弃",
                          symbol: task.isAbandoned ? "arrow.uturn.backward" : "xmark.square",
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
                    Button { openSubmenu(.group) } label: {
                        menuRow("移动到分组", symbol: "rectangle.3.group", trailing: "chevron.right")
                    }
                    .businessMenuSubmenuAction()
                    .background(activeSubmenu == .group ? WFColors.hover : .clear,
                                in: RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius))
                    .onHover { hoverRow(.group, entering: $0) }
                    .background(AnchoredPropertyPanel(
                        isPresented: submenuBinding(for: .group),
                        width: PopupMetrics.listPickerWidth, placement: .submenu, title: "移动到分组"
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
                    Button { openSubmenu(.list) } label: {
                        menuRow("移动到", symbol: "task.move", trailing: "chevron.right")
                    }
                    .businessMenuSubmenuAction()
                    .disabled(!workspace.canMoveToList(task.id))
                    // 子菜单锚在当前行，展开期间保留来源行的选中底色。
                    .background(activeSubmenu == .list ? WFColors.hover : .clear,
                                in: RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius))
                    .onHover { hoverRow(.list, entering: $0) }
                    .background(AnchoredPropertyPanel(
                        isPresented: submenuBinding(for: .list),
                        width: PopupMetrics.listPickerWidth, placement: .submenu,
                        focusPolicy: .panel, title: "移动到清单"
                    ) {
                        // 「分组是清单里面的二级菜单」：清单行再往右展开第三级面板，
                        // 列出**那个清单**的分组。选分组 = 换清单 + 落分组，一次提交。
                        TaskContextListPicker(
                            workspace: workspace,
                            selected: task.list.name,
                            currentSectionID: task.sectionID,
                            sectionHost: $sectionHost,
                            onHoverRow: { hoverListRow($0, entering: $1) },
                            onOpenSections: openSectionMenu,
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
                Button { openSubmenu(.tags) } label: {
                    menuRow("标签", symbol: "tag", trailing: "chevron.right")
                }
                .businessMenuSubmenuAction()
                .background(activeSubmenu == .tags ? WFColors.hover : .clear,
                            in: RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius))
                .onHover { hoverRow(.tags, entering: $0) }
                // 多选标签工作卡沿用共享选择器的具名宽度。
                .background(AnchoredPropertyPanel(
                    isPresented: submenuBinding(for: .tags),
                    width: PopupMetrics.tagPickerWidth, placement: .submenu,
                    focusPolicy: .panel, title: "任务标签"
                ) {
                    TaskTagPickerPopover(initialTags: task.tags, workspace: workspace,
                        onCancel: { activeSubmenu = nil },
                        onApply: { tags in
                            activeSubmenu = nil
                            perform { workspace.setTags(task.id, tags) }
                        })
                })
            }

            Divider().padding(.vertical, 2)
            focusRow
            Divider().padding(.vertical, 2)

            VStack(spacing: 0) {
                actionRow("创建副本", symbol: "square.on.square") {
                    perform { workspace.duplicate(task.id) }
                }
                actionRow("复制链接", symbol: "link") {
                    perform {
                        let copied = TaskLinkClipboard.copy(task)
                        environment.feedback.show(FeedbackEvent(kind: copied ? .success : .error,
                            message: copied ? "已复制任务链接" : "无法复制任务链接"))
                    }
                }
                actionRow("打开便签", symbol: "task.sticky") {
                    perform { StickyNoteWindowController.shared.open(taskID: task.id) }
                }
                actionRow(task.kind == .note ? "转换为任务" : "转换为笔记", symbol: "task.note") {
                    if task.kind == .note { perform { _ = workspace.setKind(task.id, .text) } }
                    else { perform { _ = environment.convertTaskToNote(task.id) } }
                }
                actionRow("删除", symbol: "trash") {
                    perform { _ = workspace.delete(task.id) }
                }
            }
            }
        }
        .padding(.top, WFSpace.xs)
        .frame(width: Self.menuWidth)
        .coordinateSpace(name: "task-context-menu")
        .coordinateSpace(name: "business-menu")
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
            Image(systemName: symbol)
                .font(.system(size: 19))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(offset == 7 ? "安排到 7 天后" : title)
        .accessibilityLabel(offset == 7 ? "7 天后" : title)
        .overlay {
            if offset == 7 {
                Text("+7").font(.system(size: 9, weight: .semibold))
                    .background(WFColors.content).offset(y: 2)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .taskContextMenuAnchor(.date(offset))
    }

    private var focusRow: some View {
        Button { openSubmenu(.focus) } label: {
            menuRow("开始专注", symbol: "smallcircle.circle", trailing: "chevron.right")
        }
        .businessMenuSubmenuAction()
        .background(activeSubmenu == .focus || activeSubmenu == .focusEstimate ? WFColors.hover : .clear,
                    in: RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius))
        .onHover { hoverRow(.focus, entering: $0) }
        .background(AnchoredPropertyPanel(isPresented: submenuBinding(for: .focus),
            width: PopupMetrics.taskMenuWidth, placement: .submenu, title: "任务专注") {
            TaskFocusSubmenu(onStart: startFocus, onSetEstimate: { openSubmenu(.focusEstimate) },
                estimateTitle: "预计番茄 / 时长", onCancel: { activeSubmenu = nil })
        })
        .background(AnchoredPropertyPanel(isPresented: submenuBinding(for: .focusEstimate),
            width: PopupMetrics.focusEstimateWidth, placement: .submenu,
            focusPolicy: .panel, title: "预计专注") {
            TaskFocusEstimateEditor(estimate: task.focusEstimate, onSave: { value in
                _ = workspace.setFocusEstimate(task.id, value)
                activeSubmenu = nil
            }, onCancel: { activeSubmenu = nil })
        })
    }

    private func openSubmenu(_ submenu: Submenu) {
        cancelPendingSubmenu()
        activeSubmenu = submenu
    }

    private func startFocus(stopwatch: Bool) {
        guard let taskID = workspace.resolveTaskForAction(task.id) else { return }
        guard environment.focusStore.start(taskID: taskID, stopwatch: stopwatch) else {
            environment.feedback.show(FeedbackEvent(kind: .error,
                message: "请先结束当前专注会话，再尝试开始新的专注。"))
            return
        }
        isPresented = false
        environment.navigation.taskSelectionToPreserveOnNextNavigation = taskID
        environment.navigate(to: .focus)
    }

    private func priorityAction(_ priority: TaskPriority, color: Color) -> some View {
        Button {
            apply { _ = workspace.setPriority(task.id, priority) }
        } label: {
            Image(systemName: priority == .none ? "flag" : "flag.fill")
                .font(.system(size: 19))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(task.priority == priority ? WFColors.selection : .clear,
                            in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(priorityTitle(priority))
        .accessibilityLabel(priorityTitle(priority))
        .taskContextMenuAnchor(.priority(priority))
    }

    private func actionRow(_ title: String, symbol: String,
                           trailing: String? = nil, disabled: Bool = false,
                           destructive: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            menuRow(title, symbol: symbol, trailing: trailing, destructive: destructive)
        }
        .disabled(disabled)
        // 普通行：鼠标落到这里就收掉正展开的子菜单（"移开自动关闭"）。
        .onHover { hoverRow(nil, entering: $0) }
    }

    private func menuRow(_ title: String, symbol: String,
                         trailing: String? = nil, destructive: Bool = false) -> some View {
        // 滴答右键菜单：文本行 34pt、图标 20pt、文字 13pt。
        HStack(spacing: 8) {
            TaskContextMenuSymbol(name: symbol).frame(width: 20, height: 20)
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Image(systemName: trailing).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WFColors.secondaryText)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(destructive ? Color.red : WFColors.text)
        .frame(minHeight: PopupMetrics.menuRowHeight)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .taskContextMenuAnchor(.action(title))
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

enum TaskContextMenuAnchor: Hashable {
    case date(Int), customDate, clearDate, priority(TaskPriority), action(String)
}
struct TaskContextMenuFrames: PreferenceKey {
    static let defaultValue: [TaskContextMenuAnchor: CGRect] = [:]
    static func reduce(value: inout [TaskContextMenuAnchor: CGRect],
                       nextValue: () -> [TaskContextMenuAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
private extension View {
    @ViewBuilder func taskContextMenuAnchor(_ anchor: TaskContextMenuAnchor) -> some View {
        #if DEBUG
        background(GeometryReader { geometry in
            Color.clear.preference(key: TaskContextMenuFrames.self,
                value: [anchor: geometry.frame(in: .named("task-context-menu"))])
        })
        #else
        self
        #endif
    }
}

/// The reference uses tree, association and folded-note outlines that do not
/// have matching SF Symbols. Draw only those glyphs; keep the system set for
/// standard actions, with the same 16-point icon column throughout the menu.
private struct TaskContextMenuSymbol: View {
    let name: String
    var body: some View {
        if name.hasPrefix("task.") {
            TaskContextMenuGlyph(name: name)
                .stroke(style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
        } else {
            Image(systemName: name).font(.system(size: 16, weight: .regular))
        }
    }
}

private struct TaskContextMenuGlyph: Shape {
    let name: String
    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch name {
        case "task.subtask":
            path.move(to: CGPoint(x: 2, y: 1))
            path.addLine(to: CGPoint(x: 2, y: 11))
            path.addQuadCurve(to: CGPoint(x: 5, y: 14), control: CGPoint(x: 2, y: 14))
            path.addLine(to: CGPoint(x: 10, y: 14))
            path.move(to: CGPoint(x: 2, y: 5))
            path.addLine(to: CGPoint(x: 10, y: 5))
            path.addEllipse(in: CGRect(x: 12, y: 4, width: 2, height: 2))
            path.addEllipse(in: CGRect(x: 12, y: 13, width: 2, height: 2))
        case "task.parent":
            path.addRoundedRect(in: CGRect(x: 4, y: 1, width: 10, height: 5), cornerSize: CGSize(width: 1.5, height: 1.5))
            path.addRoundedRect(in: CGRect(x: 4, y: 9, width: 10, height: 5), cornerSize: CGSize(width: 1.5, height: 1.5))
            path.move(to: CGPoint(x: 4, y: 11))
            path.addLine(to: CGPoint(x: 2, y: 11))
            path.addLine(to: CGPoint(x: 2, y: 4))
            path.move(to: CGPoint(x: 0.5, y: 5.5))
            path.addLine(to: CGPoint(x: 2, y: 4))
            path.addLine(to: CGPoint(x: 3.5, y: 5.5))
        case "task.pin":
            path.move(to: CGPoint(x: 1, y: 1))
            path.addLine(to: CGPoint(x: 15, y: 1))
            path.addLines([CGPoint(x: 8, y: 3), CGPoint(x: 2, y: 9), CGPoint(x: 5, y: 9), CGPoint(x: 5, y: 15),
                           CGPoint(x: 11, y: 15), CGPoint(x: 11, y: 9), CGPoint(x: 14, y: 9)])
            path.closeSubpath()
        case "task.move":
            path.addRoundedRect(in: CGRect(x: 1.5, y: 4, width: 13, height: 11), cornerSize: CGSize(width: 2, height: 2))
            path.move(to: CGPoint(x: 4, y: 1))
            path.addLine(to: CGPoint(x: 12, y: 1))
            path.move(to: CGPoint(x: 5, y: 9.5))
            path.addLine(to: CGPoint(x: 11, y: 9.5))
            path.move(to: CGPoint(x: 8.5, y: 7))
            path.addLine(to: CGPoint(x: 11, y: 9.5))
            path.addLine(to: CGPoint(x: 8.5, y: 12))
        case "task.sticky":
            path.move(to: CGPoint(x: 4, y: 1.5))
            path.addLine(to: CGPoint(x: 12, y: 1.5))
            path.addQuadCurve(to: CGPoint(x: 14.5, y: 4), control: CGPoint(x: 14.5, y: 1.5))
            path.addLine(to: CGPoint(x: 14.5, y: 9))
            path.addLine(to: CGPoint(x: 9, y: 14.5))
            path.addLine(to: CGPoint(x: 4, y: 14.5))
            path.addQuadCurve(to: CGPoint(x: 1.5, y: 12), control: CGPoint(x: 1.5, y: 14.5))
            path.addLine(to: CGPoint(x: 1.5, y: 4))
            path.addQuadCurve(to: CGPoint(x: 4, y: 1.5), control: CGPoint(x: 1.5, y: 1.5))
            path.move(to: CGPoint(x: 9, y: 14.5))
            path.addLine(to: CGPoint(x: 9, y: 11))
            path.addQuadCurve(to: CGPoint(x: 11, y: 9), control: CGPoint(x: 9, y: 9))
            path.addLine(to: CGPoint(x: 14.5, y: 9))
        case "task.note":
            path.addRoundedRect(in: CGRect(x: 1.5, y: 1, width: 11, height: 13.5), cornerSize: CGSize(width: 2, height: 2))
            path.move(to: CGPoint(x: 5, y: 1))
            path.addLine(to: CGPoint(x: 5, y: 14.5))
            path.addLines([CGPoint(x: 8, y: 1), CGPoint(x: 8, y: 6), CGPoint(x: 10, y: 4.5),
                           CGPoint(x: 12, y: 6), CGPoint(x: 12, y: 1)])
            path.addRoundedRect(in: CGRect(x: 9, y: 10, width: 6, height: 5), cornerSize: CGSize(width: 1, height: 1))
        default: break
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 16, y: rect.height / 16))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// 清单选择复用业务菜单行；点击名称移动，点击箭头或悬停展开已有分组。
private struct TaskContextListPicker: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let selected: String
    let currentSectionID: String?
    @Binding var sectionHost: String?
    let onHoverRow: (String?, Bool) -> Void
    let onOpenSections: (String) -> Void
    let onPick: (String, String?) -> Void
    let onCancel: () -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @StateObject private var controller = BusinessMenuController()

    private var matches: [String] {
        workspace.availableListNames.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(WFColors.secondaryText)
                TextField("搜索", text: $query).textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel("搜索清单")
            }
            .font(WFType.body).padding(PopupMetrics.contentInset)
            .taskContextSubmenuAnchor(.search)
            .onHover { onHoverRow(nil, $0) }
            Divider()
            BusinessMenuContent(controller: controller, close: onCancel, dismissAll: {}) {
                ForEach(matches, id: \.self) { name in
                    TaskContextListChoice(workspace: workspace, controller: controller, name: name,
                        selected: name == selected, currentSectionID: name == selected ? currentSectionID : nil,
                        sectionHost: $sectionHost, onHoverRow: onHoverRow,
                        onOpenSections: onOpenSections, onPick: onPick)
                }
                if matches.isEmpty {
                    Text("没有匹配的清单").font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText).padding(12)
                }
            }
        }
        .frame(width: PopupMetrics.listPickerWidth)
        .coordinateSpace(name: "task-context-submenu")
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
        .onChange(of: query) { _, _ in sectionHost = nil; controller.reset() }
        .onExitCommand(perform: onCancel)
    }
}

private struct TaskContextListChoice: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var controller: BusinessMenuController
    let name: String
    let selected: Bool
    let currentSectionID: String?
    @Binding var sectionHost: String?
    let onHoverRow: (String?, Bool) -> Void
    let onOpenSections: (String) -> Void
    let onPick: (String, String?) -> Void
    @State private var identity = UUID()

    private var offersSections: Bool { !workspace.listSections(forList: name).isEmpty }

    var body: some View {
        BusinessMenuRow(controller: controller, id: identity, submenu: offersSections,
            activate: { onPick(name, nil) }, hover: { inside in
                if inside { controller.highlighted = identity }
                onHoverRow(offersSections ? name : nil, inside)
            }, openSubmenu: offersSections ? { onOpenSections(name) } : nil) {
            HStack(spacing: 8) {
                if name == TaskList.inbox.name {
                    Image(systemName: "tray").frame(width: 16)
                } else if let icon = workspace.listMeta(for: name)?.icon {
                    Text(icon).frame(width: 16)
                } else {
                    Image(systemName: "list.bullet").frame(width: 16)
                }
                Text(name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                    .frame(width: 14).opacity(selected ? 1 : 0)
            }.foregroundStyle(selected ? WFColors.accent : WFColors.text)
        }
        .accessibilityLabel(name).accessibilityValue(selected ? "已选择" : "未选择")
        .taskContextSubmenuAnchor(.list(name))
        .background(AnchoredPropertyPanel(
            isPresented: Binding(get: { offersSections && sectionHost == name },
                set: { if !$0, sectionHost == name { sectionHost = nil } }),
            width: PopupMetrics.listPickerWidth, placement: .submenu, title: "移动到分组") {
            TaskContextSectionPicker(workspace: workspace, listName: name,
                selected: currentSectionID, onCancel: { sectionHost = nil },
                onSelect: { onPick(name, $0) })
        })
    }
}

/// 分组选择与即时移动；创建分组使用同一窗口链中的轻量表单。
private struct TaskContextSectionPicker: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let listName: String
    let selected: String?
    let onCancel: () -> Void
    let onSelect: (String?) -> Void
    @State private var showAdd = false
    @StateObject private var controller = BusinessMenuController()

    var body: some View {
        BusinessMenuContent(controller: controller, close: onCancel, dismissAll: {}) {
            ForEach(workspace.listSections(forList: listName)) { section in
                BusinessMenuOption(section.title, selected: section.id == selected, symbol: "rectangle.3.group") {
                    if selected != section.id { onSelect(section.id) }
                }.taskContextSubmenuAnchor(.section(section.id))
            }
            if workspace.listSections(forList: listName).isEmpty {
                Text("这个清单还没有分组").font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText).padding(10)
            }
            if selected != nil {
                BusinessMenuOption("移出分组", symbol: "minus.circle") { onSelect(nil) }
                    .taskContextSubmenuAnchor(.clearSection)
            }
            Divider().padding(.vertical, 2)
            Button("添加分组…", systemImage: "plus") { showAdd = true }
                .taskContextSubmenuAnchor(.addSection)
                .background(AnchoredPropertyPanel(isPresented: $showAdd,
                    width: PopupMetrics.parentPickerWidth, placement: .submenu,
                    focusPolicy: .panel, title: "添加分组") {
                    TaskContextSectionForm(onCancel: { showAdd = false }, onSave: { title in
                        guard workspace.addListSection(listName, title: title),
                              let section = workspace.listSections(forList: listName).first(where: { $0.title == title })
                        else { return false }
                        showAdd = false
                        onSelect(section.id)
                        return true
                    })
                })
        }
        .frame(width: PopupMetrics.listPickerWidth)
        .coordinateSpace(name: "task-context-submenu")
        .onExitCommand(perform: onCancel)
    }
}

private struct TaskContextSectionForm: View {
    let onCancel: () -> Void
    let onSave: (String) -> Bool
    @State private var title = ""
    @State private var error: String?
    private var name: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("添加分组").font(WFType.sectionSemibold)
                TextField("分组名称", text: $title).textFieldStyle(.roundedBorder).onSubmit(save)
                Text(error ?? " ").font(WFType.supporting).foregroundStyle(WFColors.danger)
                    .lineLimit(1).frame(height: 17)
            }.padding(PopupMetrics.contentInset)
            PopupActionBar {
                PopupActionButton(title: "取消", action: onCancel).keyboardShortcut(.cancelAction)
                PopupActionButton(title: "添加", primary: true, action: save)
                    .disabled(name.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .font(WFType.body).frame(width: PopupMetrics.parentPickerWidth)
        .onChange(of: title) { _, _ in error = nil }
    }

    private func save() {
        guard !name.isEmpty else { return }
        if !onSave(name) { error = "无法添加，请检查名称是否重复。" }
    }
}

enum TaskContextSubmenuAnchor: Hashable {
    case search, list(String), section(String), clearSection, addSection
}
struct TaskContextSubmenuFrames: PreferenceKey {
    static let defaultValue: [TaskContextSubmenuAnchor: CGRect] = [:]
    static func reduce(value: inout [TaskContextSubmenuAnchor: CGRect],
                       nextValue: () -> [TaskContextSubmenuAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
private extension View {
    @ViewBuilder func taskContextSubmenuAnchor(_ anchor: TaskContextSubmenuAnchor) -> some View {
        #if DEBUG
        background(GeometryReader { geometry in
            Color.clear.preference(key: TaskContextSubmenuFrames.self,
                value: [anchor: geometry.frame(in: .named("task-context-submenu"))])
        })
        #else
        self
        #endif
    }
}
