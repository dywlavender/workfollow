import SwiftUI

enum TaskTreeRenderPart: Hashable { case disclosure, checkbox, title, preview, date, row }
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
#if DEBUG
private struct TaskTreeFrameRecordingKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    /// Geometry instrumentation is opt-in for render tests, not ordinary pages.
    var recordsTaskTreeFrames: Bool {
        get { self[TaskTreeFrameRecordingKey.self] }
        set { self[TaskTreeFrameRecordingKey.self] = newValue }
    }
}
private struct TaskTreeFrameRecorder: ViewModifier {
    @Environment(\.recordsTaskTreeFrames) private var enabled
    let taskID: UUID
    let part: TaskTreeRenderPart
    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.background {
                GeometryReader { geometry in
                    Color.clear.preference(key: TaskTreeFramesKey.self,
                        value: [TaskTreeRenderAnchor(taskID: taskID, part: part):
                            geometry.frame(in: .named("task-tree-render"))])
                }
            }
        } else {
            content
        }
    }
}
#endif
extension View {
    @ViewBuilder
    func taskTreeRenderAnchor(_ taskID: UUID, _ part: TaskTreeRenderPart) -> some View {
        #if DEBUG
        modifier(TaskTreeFrameRecorder(taskID: taskID, part: part))
        #else
        self
        #endif
    }
}
