import SwiftUI

enum QuickAddRenderAnchor: Hashable {
    case priority(TaskPriority), list, tags, template, properties
}

struct QuickAddFramesKey: PreferenceKey {
    static var defaultValue: [QuickAddRenderAnchor: CGRect] = [:]
    static func reduce(value: inout [QuickAddRenderAnchor: CGRect], nextValue: () -> [QuickAddRenderAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func quickAddRenderAnchor(_ anchor: QuickAddRenderAnchor) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: QuickAddFramesKey.self,
                value: [anchor: geometry.frame(in: .named("quick-add-render"))])
        })
    }
}
