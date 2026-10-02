import SwiftUI

enum TaskRelationPickerAnchor: Hashable { case target(String), panel }
struct TaskRelationPickerFrames: PreferenceKey {
    static let defaultValue: [TaskRelationPickerAnchor: CGRect] = [:]
    static func reduce(value: inout [TaskRelationPickerAnchor: CGRect], nextValue: () -> [TaskRelationPickerAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
private extension View {
    @ViewBuilder
    func relationPickerAnchor(_ anchor: TaskRelationPickerAnchor) -> some View {
        #if DEBUG
        background(GeometryReader { geometry in
            Color.clear.preference(key: TaskRelationPickerFrames.self,
                value: [anchor: geometry.frame(in: .named("task-relation-picker"))])
        })
        #else
        self
        #endif
    }
}

/// Existing picker presentation retained; selecting commits one reference.
struct TaskRelationPicker: View {
    let sourceTaskID: UUID
    let tasks: [Task]
    let notes: [Note]
    let sourceNoteID: UUID?
    let onSelect: (TaskRelationTarget) -> Bool
    let onCancel: () -> Void
    @State private var query = ""
    @State private var failed = false

    private var targets: [TaskRelationTarget] {
        TaskRelationProjection.targets(sourceTaskID: sourceTaskID, tasks: tasks, notes: notes, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("搜索任务或笔记", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if targets.isEmpty {
                        Text("没有匹配的任务或笔记").foregroundStyle(.secondary).padding()
                    }
                    ForEach(targets) { target in
                        Button { failed = !onSelect(target) } label: {
                            HStack {
                                Image(systemName: target.symbol)
                                VStack(alignment: .leading) {
                                    Text(target.title).lineLimit(1)
                                    Text(target.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if case let .note(note) = target, sourceNoteID == note.id {
                                    Image(systemName: "checkmark")
                                }
                            }.padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain).relationPickerAnchor(.target(target.id))
                    }
                }
            }
            if failed {
                Text("无法插入关联，请返回正文后重试").font(.caption).foregroundStyle(.red)
            }
        }.padding(16).frame(width: 320, height: 300)
            .coordinateSpace(name: "task-relation-picker")
            .relationPickerAnchor(.panel)
            .background(PopupEscapeRouter(depth: 2, onEscape: onCancel))
            .onExitCommand(perform: onCancel)
    }
}
