import SwiftUI

struct TaskListView: View {
    @ObservedObject var workspace: PreviewWorkspace
    let navigationVisible: Bool
    @EnvironmentObject private var environment: AppEnvironment
    @State private var draft = ""
    @State private var showNavigation = false
    @FocusState private var quickAddFocused: Bool
    @FocusState private var listFocused: Bool

    private var canAdd: Bool { [.today, .inbox].contains(workspace.destination) }

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.lg) {
            HStack(spacing: WFSpace.md) {
                if !navigationVisible {
                    Button { showNavigation.toggle() } label: {
                        Image(systemName: "sidebar.left")
                    }.buttonStyle(.plain).help("显示导航")
                        .popover(isPresented: $showNavigation) {
                            NavigationColumnView(workspace: workspace) { showNavigation = false }
                                .frame(width: WFMetrics.navigationWidth, height: 260)
                        }
                }
                Label(workspace.destination.title, systemImage: workspace.destination.symbol)
                    .font(WFType.pageTitle)
                Spacer(minLength: 0)
                Text("\(workspace.visibleTasks.count)")
                    .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            }
            .padding(.horizontal, WFSpace.xl)
            .padding(.top, WFSpace.xl)

            if canAdd {
                HStack(spacing: WFSpace.sm) {
                    Image(systemName: "plus").foregroundStyle(WFColors.secondaryText)
                    TextField("添加任务至收集箱", text: $draft)
                        .textFieldStyle(.plain).font(WFType.body)
                        .focused($quickAddFocused)
                        .onSubmit(addTask)
                    if workspace.destination == .today {
                        Image(systemName: "calendar")
                            .foregroundStyle(WFColors.accent).help("今天")
                    }
                }
                .padding(WFSpace.md)
                .background(WFColors.secondarySurface,
                            in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .padding(.horizontal, WFSpace.xl)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    if workspace.visibleTasks.isEmpty {
                        Text(workspace.destination == .trash ? "垃圾桶是空的" : "这里还没有任务")
                            .font(WFType.body).foregroundStyle(WFColors.secondaryText)
                            .frame(maxWidth: .infinity).padding(.vertical, WFSpace.page)
                    }
                    ForEach(workspace.visibleTasks) { task in
                        PreviewTaskRow(task: task,
                                       selected: workspace.selectedTaskID == task.id,
                                       onSelect: {
                                           listFocused = true
                                           workspace.select(task.id)
                                       },
                                       onComplete: { workspace.toggleCompletion(task.id) })
                        Divider().padding(.leading, WFSpace.page)
                    }
                }
                .padding(.horizontal, WFSpace.md)
                .padding(.bottom, WFSpace.xl)
            }
            .focusable()
            .focused($listFocused)
            .onKeyPress(.upArrow) {
                guard !quickAddFocused else { return .ignored }
                workspace.selectAdjacent(-1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                guard !quickAddFocused else { return .ignored }
                workspace.selectAdjacent(1)
                return .handled
            }
            .onKeyPress(.return) {
                guard !quickAddFocused else { return .ignored }
                if workspace.selectedTaskID == nil { workspace.selectAdjacent(1) }
                return .handled
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WFColors.content)
        .onChange(of: environment.quickAddRequest) { _, _ in quickAddFocused = true }
        .onAppear {
            if environment.quickAddRequest > 0 { quickAddFocused = true }
            else { listFocused = true }
        }
        .onExitCommand {
            // Leaving quick-add must not dismiss a wide-screen inspector.
            quickAddFocused = false
        }
    }

    private func addTask() {
        workspace.addTask(draft)
        draft = ""
    }
}

private struct PreviewTaskRow: View {
    let task: PreviewTask
    let selected: Bool
    let onSelect: () -> Void
    let onComplete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: WFSpace.sm) {
            Button(action: onComplete) {
                Image(systemName: task.completed ? "checkmark.square.fill" : "square")
                    .font(.system(size: WFMetrics.icon))
                    .foregroundStyle(task.completed ? WFColors.tertiaryText
                                     : task.priority ? .orange : WFColors.secondaryText)
                    .frame(width: WFSpace.xxl, height: WFMetrics.controlHeight)
            }
            .buttonStyle(.plain)
            .help(task.completed ? "恢复任务" : "完成任务")
            .accessibilityLabel(task.completed ? "恢复：\(task.title)" : "完成：\(task.title)")

            Button(action: onSelect) {
                HStack(spacing: WFSpace.sm) {
                    Text(task.title).font(WFType.listTitle).lineLimit(1)
                        .foregroundStyle(task.completed ? WFColors.secondaryText : WFColors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(task.list).font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText).lineLimit(1)
                    if task.scheduledToday {
                        Text("今天").font(WFType.supporting)
                            .foregroundStyle(task.completed ? WFColors.tertiaryText : WFColors.accent)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: WFMetrics.rowHeight)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, WFSpace.sm)
        .background(selected ? WFColors.selection : hovering ? WFColors.hover : .clear,
                    in: RoundedRectangle(cornerRadius: WFMetrics.corner))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("打开任务", action: onSelect)
            Button(task.completed ? "恢复任务" : "完成任务", action: onComplete)
        }
    }
}
