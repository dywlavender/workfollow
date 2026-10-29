import SwiftUI

enum TaskParentPickerAnchor: Hashable { case candidate(UUID), confirm }
struct TaskParentPickerFrames: PreferenceKey {
    static let defaultValue: [TaskParentPickerAnchor: CGRect] = [:]
    static func reduce(value: inout [TaskParentPickerAnchor: CGRect], nextValue: () -> [TaskParentPickerAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
private extension View {
    @ViewBuilder
    func parentPickerAnchor(_ anchor: TaskParentPickerAnchor) -> some View {
        #if DEBUG
        background(GeometryReader { geometry in
            Color.clear.preference(key: TaskParentPickerFrames.self,
                value: [anchor: geometry.frame(in: .named("parent-picker"))])
        })
        #else
        self
        #endif
    }
}

enum TaskParentPickerProjection {
    static func candidates(for taskID: UUID, tasks: [Task], query: String) -> [Task] {
        candidates(for: Set([taskID]), tasks: tasks, query: query)
    }

    static func candidates(for taskIDs: Set<UUID>, tasks: [Task], query: String) -> [Task] {
        let sources = tasks.filter { taskIDs.contains($0.id) }
        guard !sources.isEmpty, sources.count == taskIDs.count else { return [] }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.filter { candidate in
            !taskIDs.contains(candidate.id) && !candidate.isNoteTask &&
            sources.allSatisfy({ TaskParentPolicy.canAssign(task: $0, parent: candidate, tasks: tasks) }) &&
            (text.isEmpty || candidate.title.localizedCaseInsensitiveContains(text) ||
             candidate.list.name.localizedCaseInsensitiveContains(text))
        }.sorted {
            if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return $0.createdAt < $1.createdAt
        }
    }
}

/// Browsing/searching is draft-only. A batch uses the complete source selection
/// for both candidate validation and its one-step assignment command.
struct TaskParentPicker: View {
    private let taskIDs: Set<UUID>
    private let isBulkAssignment: Bool
    @ObservedObject var workspace: TaskWorkspaceModel
    let onClose: () -> Void
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var failed = false
    @FocusState private var searchFocused: Bool

    init(taskID: UUID, workspace: TaskWorkspaceModel, onClose: @escaping () -> Void) {
        self.taskIDs = [taskID]
        self.isBulkAssignment = false
        self.workspace = workspace
        self.onClose = onClose
    }

    init(taskIDs: Set<UUID>, workspace: TaskWorkspaceModel, onClose: @escaping () -> Void) {
        self.taskIDs = taskIDs
        self.isBulkAssignment = true
        self.workspace = workspace
        self.onClose = onClose
    }

    private var candidates: [Task] {
        TaskParentPickerProjection.candidates(for: taskIDs, tasks: workspace.allTasks, query: query)
            .filter { !workspace.isListArchived($0.list.name) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("关联主任务").font(WFType.menu).padding(.top, 12)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(WFColors.secondaryText)
                TextField("搜索任务或清单", text: $query).textFieldStyle(.plain)
                    .focused($searchFocused)
            }.padding(12)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    if candidates.isEmpty {
                        Text("没有可关联的主任务").font(WFType.body)
                            .foregroundStyle(WFColors.secondaryText).padding(.vertical, 28)
                    }
                    ForEach(candidates) { task in
                        Button { selectedID = task.id; failed = false } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title.isEmpty ? "无标题" : task.title).lineLimit(1)
                                    Text(task.list.name).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                                }
                                Spacer()
                                if selectedID == task.id { Image(systemName: "checkmark").foregroundStyle(WFColors.accent) }
                            }.frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                                .padding(.horizontal, 12).contentShape(Rectangle())
                                .rowHoverBackground(cornerRadius: 6)
                        }.buttonStyle(.plain).parentPickerAnchor(.candidate(task.id))
                    }
                }
                .compactScrollbars()
            }
            if failed {
                Text("任务状态已变化，请重新选择").font(WFType.supporting).foregroundStyle(.red).padding(8)
            }
            PopupActionBar {
                PopupActionButton(title: "取消", action: onClose)
                PopupActionButton(title: "确定", primary: true) {
                    guard let selectedID else { return }
                    let result: TaskActionResult
                    if isBulkAssignment {
                        result = workspace.assignBulkParent(taskIDs, parentID: selectedID)
                    } else if let taskID = taskIDs.first {
                        result = workspace.assignParent(taskID, parentID: selectedID)
                    } else { return }
                    if result.taskID != nil { onClose() }
                    else { failed = true; self.selectedID = nil }
                }.disabled(!candidates.contains { $0.id == selectedID })
                    .parentPickerAnchor(.confirm)
            }
        }.frame(width: PopupMetrics.parentPickerWidth, height: 340)
            .coordinateSpace(name: "parent-picker")
            .onAppear {
                searchFocused = true
                if !isBulkAssignment, let taskID = taskIDs.first {
                    selectedID = workspace.task(for: taskID)?.parentID
                }
            }
            .onExitCommand(perform: onClose)
            .onKeyPress(.escape) { onClose(); return .handled }
    }
}
