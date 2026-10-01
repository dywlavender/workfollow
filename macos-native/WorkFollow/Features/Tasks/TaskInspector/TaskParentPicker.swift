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
        guard let source = tasks.first(where: { $0.id == taskID }) else { return [] }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.filter {
            TaskParentPolicy.canAssign(task: source, parent: $0, tasks: tasks) &&
            (text.isEmpty || $0.title.localizedCaseInsensitiveContains(text) ||
             $0.list.name.localizedCaseInsensitiveContains(text))
        }.sorted {
            if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return $0.createdAt < $1.createdAt
        }
    }
}

/// Single-selection draft: browsing/searching never changes task hierarchy.
struct TaskParentPicker: View {
    let taskID: UUID
    @ObservedObject var workspace: TaskWorkspaceModel
    let onClose: () -> Void
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var failed = false
    @FocusState private var searchFocused: Bool

    private var candidates: [Task] {
        TaskParentPickerProjection.candidates(for: taskID, tasks: workspace.allTasks, query: query)
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
                        }.buttonStyle(.plain).parentPickerAnchor(.candidate(task.id))
                    }
                }
            }
            if failed {
                Text("任务状态已变化，请重新选择").font(WFType.supporting).foregroundStyle(.red).padding(8)
            }
            Divider()
            HStack {
                Button("取消", action: onClose).frame(maxWidth: .infinity)
                Button("确定") {
                    guard let selectedID else { return }
                    if workspace.assignParent(taskID, parentID: selectedID).taskID != nil { onClose() }
                    else { failed = true; self.selectedID = nil }
                }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    .disabled(!candidates.contains { $0.id == selectedID })
                    .parentPickerAnchor(.confirm)
            }.padding(12)
        }.frame(width: 280, height: 340)
            .coordinateSpace(name: "parent-picker")
            .onAppear { searchFocused = true; selectedID = workspace.task(for: taskID)?.parentID }
            .onExitCommand(perform: onClose)
            .onKeyPress(.escape) { onClose(); return .handled }
    }
}
