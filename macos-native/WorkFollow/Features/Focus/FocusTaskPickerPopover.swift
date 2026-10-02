import SwiftUI

struct FocusTaskPickerLayoutPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

private struct FocusTaskPickerLayoutAnchor: ViewModifier {
    let key: String

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: FocusTaskPickerLayoutPreferenceKey.self,
                    value: [key: geometry.frame(in: .named("focus-task-picker"))]
                )
            }
        }
    }
}

private extension View {
    func focusTaskPickerAnchor(_ key: String) -> some View {
        modifier(FocusTaskPickerLayoutAnchor(key: key))
    }
}

enum FocusTaskPickerMetrics {
    static let width: CGFloat = 312
    static let height: CGFloat = 460
    static let cornerRadius: CGFloat = 14
    static let outerPadding: CGFloat = 16
    static let searchHeight: CGFloat = 34
    static let scopeRowHeight: CGFloat = 34
    static let groupHeaderHeight: CGFloat = 26
    static let taskRowHeight: CGFloat = 36
    static let checkboxSize: CGFloat = 14
    static let taskFontSize: CGFloat = 13
    static let dateFontSize: CGFloat = 11
    static let scopeWidth: CGFloat = 172
    static let scopeRowHeightCompact: CGFloat = 34
    static let scopeHorizontalPadding: CGFloat = 12
    static let scopeIconSize: CGFloat = 15
}

struct FocusTaskPickerPopover: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let selectedTaskID: UUID?
    @Binding var scope: FocusTaskPickerScope
    @Binding var query: String
    @Binding var isScopePickerPresented: Bool
    let onSelectScope: (FocusTaskPickerScope) -> Void
    let onSelectTask: (Task) -> Void
    let onClearTask: () -> Void

    init(workspace: TaskWorkspaceModel, selectedTaskID: UUID?,
         scope: Binding<FocusTaskPickerScope>, query: Binding<String>,
         isScopePickerPresented: Binding<Bool>,
         onSelectScope: @escaping (FocusTaskPickerScope) -> Void,
         onSelectTask: @escaping (Task) -> Void,
         onClearTask: @escaping () -> Void,
         onDismiss _: () -> Void = {}) {
        self.workspace = workspace
        self.selectedTaskID = selectedTaskID
        self._scope = scope
        self._query = query
        self._isScopePickerPresented = isScopePickerPresented
        self.onSelectScope = onSelectScope
        self.onSelectTask = onSelectTask
        self.onClearTask = onClearTask
    }

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchFocused: Bool
    @State private var isScopeHovered = false

    private var theme: FocusTheme { FocusTheme(colorScheme) }

    private var groups: [FocusTaskPickerGroup] {
        FocusTaskPickerProjection.groups(
            tasks: workspace.allTasks,
            scope: scope,
            query: query,
            now: workspace.clock(),
            calendar: workspace.calendar
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .focusTaskPickerAnchor("search")
                .padding(.bottom, 8)

            scopeButton
                .focusTaskPickerAnchor("scope")
                .padding(.bottom, 9)

            Divider()

            ScrollView {
                if groups.isEmpty {
                    Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "没有任务" : "没有匹配的任务")
                        .font(.system(size: FocusTaskPickerMetrics.taskFontSize))
                        .foregroundStyle(theme.text3)
                        .frame(maxWidth: .infinity, minHeight: 104)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { group in
                            if let title = group.title {
                                Text(title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(theme.text2)
                                    .frame(maxWidth: .infinity, minHeight: FocusTaskPickerMetrics.groupHeaderHeight,
                                           alignment: .leading)
                                    .padding(.horizontal, 8)
                            }
                            ForEach(group.tasks) { task in
                                taskRow(task)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.automatic)

            if selectedTaskID != nil {
                Divider().padding(.top, 6)
                Button(action: onClearTask) {
                    Label("不关联", systemImage: "xmark.circle")
                        .font(.system(size: FocusTaskPickerMetrics.taskFontSize))
                        .foregroundStyle(theme.text2)
                        .frame(maxWidth: .infinity, minHeight: FocusTaskPickerMetrics.taskRowHeight,
                               alignment: .leading)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("focus-task-picker-clear")
            }
        }
        .padding(FocusTaskPickerMetrics.outerPadding)
        .frame(width: FocusTaskPickerMetrics.width, height: FocusTaskPickerMetrics.height,
               alignment: .topLeading)
        .coordinateSpace(name: "focus-task-picker")
        .background(theme.canvas, in: RoundedRectangle(cornerRadius: FocusTaskPickerMetrics.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: FocusTaskPickerMetrics.cornerRadius)
            .stroke(theme.hairline, lineWidth: 1))
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(theme.text3)
            TextField("搜索", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: FocusTaskPickerMetrics.taskFontSize))
                .focused($searchFocused)
                .accessibilityIdentifier("focus-task-picker-search")
        }
        .padding(.horizontal, 10)
        .frame(height: FocusTaskPickerMetrics.searchHeight)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.chipBackground))
    }

    private var scopeButton: some View {
        Button {
            isScopePickerPresented = true
        } label: {
            HStack(spacing: 8) {
                scopeIcon(scope)
                Text(scope.title)
                    .font(.system(size: FocusTaskPickerMetrics.taskFontSize, weight: .medium))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.text3)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity,
                   minHeight: FocusTaskPickerMetrics.scopeRowHeight,
                   maxHeight: FocusTaskPickerMetrics.scopeRowHeight)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(isScopeHovered ? theme.chipBackground : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("focus-task-picker-scope")
        .onHover { isScopeHovered = $0 }
        .background(AnchoredPropertyPanel(
            isPresented: $isScopePickerPresented,
            width: FocusTaskPickerMetrics.scopeWidth,
            placement: .submenu
        ) {
            FocusTaskScopePopover(
                selectedScope: scope,
                listNames: workspace.orderedListNames,
                listColor: { name in
                    WFPlanningPalette.listColor(name: name, meta: workspace.listMeta(for: name))
                },
                onSelect: onSelectScope,
                onDismiss: { isScopePickerPresented = false }
            )
        })
    }

    private func scopeIcon(_ value: FocusTaskPickerScope) -> some View {
        Group {
            if case let .list(name) = value {
                Circle().fill(WFPlanningPalette.listColor(name: name,
                                                          meta: workspace.listMeta(for: name)))
            } else {
                Image(systemName: value.symbol)
                    .foregroundStyle(theme.text2)
            }
        }
        .frame(width: 16, height: 16)
    }

    private func taskRow(_ task: Task) -> some View {
        Button { onSelectTask(task) } label: {
            HStack(spacing: 8) {
                Circle()
                    .stroke(theme.text3, lineWidth: 1.35)
                    .frame(width: FocusTaskPickerMetrics.checkboxSize,
                           height: FocusTaskPickerMetrics.checkboxSize)
                Text(FocusTaskPickerProjection.displayTitle(for: task))
                    .font(.system(size: FocusTaskPickerMetrics.taskFontSize))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let date = FocusTaskPickerProjection.date(for: task) {
                    Text(dateText(date, task: task))
                        .font(.system(size: FocusTaskPickerMetrics.dateFontSize))
                        .foregroundStyle(dateIsOverdue(date) ? theme.warn : theme.text3)
                        .lineLimit(1)
                        .fixedSize()
                        .focusTaskPickerAnchor("date-\(task.id.uuidString)")
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: FocusTaskPickerMetrics.taskRowHeight)
            .background(task.id == selectedTaskID
                        ? WFColors.selection.opacity(0.55) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusTaskPickerAnchor("task-\(task.id.uuidString)")
        .accessibilityLabel("选择专注任务：\(FocusTaskPickerProjection.displayTitle(for: task))")
        .accessibilityIdentifier("focus-task-picker-task-\(task.id.uuidString)")
    }

    private func dateText(_ date: Date, task: Task) -> String {
        let hasTime = task.schedule.dueAt != nil && task.schedule.hasTime
        let label = TaskDateLabel.text(date, hasTime: hasTime, now: workspace.clock(),
                                       calendar: workspace.calendar)
        return task.schedule.dueAt == nil ? label + "截止" : label
    }

    private func dateIsOverdue(_ date: Date) -> Bool {
        workspace.calendar.startOfDay(for: date) < workspace.calendar.startOfDay(for: workspace.clock())
    }
}
