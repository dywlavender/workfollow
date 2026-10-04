import SwiftUI

struct TaskContextMenuPopover: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @Binding var isPresented: Bool
    let task: Task
    let onCustomDate: () -> Void
    @EnvironmentObject private var environment: AppEnvironment
    private enum Submenu: Equatable { case list, tags }
    @State private var activeSubmenu: Submenu?
    @State private var submenuHoverTimer: DispatchWorkItem?

    /// 面板宽度对齐 Flutter TaskMenuMetrics.width = 264。
    static let menuWidth: CGFloat = 264

    /// 悬浮多久后展开子菜单，对齐 Flutter WorkFollowMotion.submenuIntent（220ms）。
    private static let submenuIntent: TimeInterval = 0.22

    /// 悬浮带子菜单的行时延迟展开；已有子菜单打开时不抢占（对齐 Flutter
    /// `_openSubmenu` 的 `submenu != null` 守卫）。
    private func hoverOpensSubmenu(_ entering: Bool, open: @escaping () -> Void) {
        submenuHoverTimer?.cancel()
        guard entering, activeSubmenu == nil else { return }
        let work = DispatchWorkItem { open() }
        submenuHoverTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.submenuIntent, execute: work)
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
                    perform { _ = workspace.clearDueDate(task.id) }
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
                actionRow("开始专注", symbol: "timer") {
                    perform { environment.startFocus(for: task.id) }
                }
                if task.parentID == nil {
                    actionRow("添加子任务", symbol: "plus.square.on.square") {
                        perform { _ = workspace.requestChildTitleEditor(for: task.id) }
                    }
                }
                actionRow(task.isPinned ? "取消置顶" : "置顶", symbol: "pin") {
                    perform { _ = workspace.setPinned(task.id, !task.isPinned) }
                }
                // 复制任务（Round B1，对齐 Flutter）：连同子任务生成副本，HUD 自动带撤销。
                actionRow("复制任务", symbol: "doc.on.doc") {
                    perform { workspace.duplicate(task.id) }
                }
                actionRow(task.isAbandoned ? "恢复任务" : "放弃任务",
                          symbol: task.isAbandoned ? "arrow.uturn.backward" : "xmark.circle",
                          disabled: task.status == .completed && !task.isAbandoned) {
                    perform {
                        if task.isAbandoned { _ = workspace.restore(task.id) }
                        else { _ = workspace.abandon(task.id) }
                    }
                }
                if task.parentID == nil {
                    Button { activeSubmenu = .list } label: {
                        menuRow("移动到清单", symbol: "tray.full", trailing: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .disabled(!workspace.canMoveToList(task.id))
                    // Flutter：子菜单挂到行右侧（gap 14），展开期间行保持选中底色。
                    .background(activeSubmenu == .list ? WFColors.selection : .clear,
                                in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                    .onHover { hoverOpensSubmenu($0) { activeSubmenu = .list } }
                    .background(AnchoredPropertyPanel(
                        isPresented: submenuBinding(for: .list),
                        width: 196, placement: .submenu
                    ) {
                        TaskContextListPicker(workspace: workspace, selected: task.list.name,
                            onCancel: { activeSubmenu = nil },
                            onSelect: { name in
                                activeSubmenu = nil
                                perform { _ = workspace.moveToList(task.id, TaskList(name: name)) }
                            })
                    })
                }
                Button { activeSubmenu = .tags } label: {
                    menuRow("标签", symbol: "tag", trailing: "chevron.right")
                }
                .buttonStyle(.plain)
                .background(activeSubmenu == .tags ? WFColors.selection : .clear,
                            in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .onHover { hoverOpensSubmenu($0) { activeSubmenu = .tags } }
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
            }

            Divider().padding(.vertical, WFSpace.xs)
            actionRow("转换为笔记", symbol: "doc.text") {
                perform { _ = environment.convertTaskToNote(task.id) }
            }
            actionRow("删除任务", symbol: "trash", destructive: true) {
                perform { _ = workspace.delete(task.id) }
            }
        }
        .padding(.vertical, WFSpace.xs)
        .frame(width: Self.menuWidth)
        .onExitCommand { isPresented = false }
        .onDisappear {
            submenuHoverTimer?.cancel()
            submenuHoverTimer = nil
        }
    }

    private func dateAction(_ title: String, symbol: String, offset: Int) -> some View {
        Button {
            perform { _ = workspace.moveDueDate(task.id, to: workspace.dateFromToday(offset)) }
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
            perform { _ = workspace.setPriority(task.id, priority) }
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

    private func perform(_ action: () -> Void) {
        isPresented = false
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

private struct TaskContextListPicker: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let selected: String
    let onCancel: () -> Void
    let onSelect: (String) -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var matches: [String] {
        workspace.allListNames.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(WFColors.secondaryText)
                TextField("搜索清单", text: $query).textFieldStyle(.plain).focused($searchFocused)
            }
            .padding(WFSpace.md)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(matches, id: \.self) { name in
                        Button { onSelect(name) } label: {
                            HStack(spacing: WFSpace.md) {
                                Image(systemName: name == TaskList.inbox.name ? "tray" : "list.bullet")
                                    .foregroundStyle(WFColors.secondaryText)
                                Text(name).frame(maxWidth: .infinity, alignment: .leading)
                                if name == selected { Image(systemName: "checkmark").foregroundStyle(WFColors.accent) }
                            }
                            .padding(.horizontal, WFSpace.md)
                            .frame(height: WFMetrics.controlHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
}
