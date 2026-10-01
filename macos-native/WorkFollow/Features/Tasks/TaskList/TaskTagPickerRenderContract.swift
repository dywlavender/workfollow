import SwiftUI

enum TaskTagPickerAnchor: Hashable { case tag(String), cancel, confirm }
struct TaskTagPickerFrames: PreferenceKey {
    static let defaultValue: [TaskTagPickerAnchor: CGRect] = [:]
    static func reduce(value: inout [TaskTagPickerAnchor: CGRect], nextValue: () -> [TaskTagPickerAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
extension View {
    @ViewBuilder
    func tagPickerRenderAnchor(_ anchor: TaskTagPickerAnchor) -> some View {
        #if DEBUG
        background(GeometryReader { geometry in
            Color.clear.preference(key: TaskTagPickerFrames.self,
                value: [anchor: geometry.frame(in: .named("task-tag-picker"))])
        })
        #else
        self
        #endif
    }
}
