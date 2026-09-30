import SwiftUI

enum TaskTreeRenderPart: Hashable { case disclosure, checkbox, preview }
struct TaskTreeRenderAnchor: Hashable {
    let taskID: UUID
    let part: TaskTreeRenderPart
}
struct TaskTreeFramesKey: PreferenceKey {
    static let defaultValue: [TaskTreeRenderAnchor: CGRect] = [:]
    static func reduce(value: inout [TaskTreeRenderAnchor: CGRect],
                       nextValue: () -> [TaskTreeRenderAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
extension View {
    @ViewBuilder
    func taskTreeRenderAnchor(_ taskID: UUID, _ part: TaskTreeRenderPart) -> some View {
        #if DEBUG
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: TaskTreeFramesKey.self,
                    value: [TaskTreeRenderAnchor(taskID: taskID, part: part):
                        geometry.frame(in: .named("task-tree-render"))])
            }
        }
        #else
        self
        #endif
    }
}
