import SwiftUI

enum InspectorRenderAnchor: Hashable {
    case header, back, completion, divider, schedule, scheduleViewport
    case reminder, repeatControl, priority, breadcrumb, title, emptyContent
    case document, childSection, childRow(UUID), addChild
    case footerList, footerFormatting, footerMore
    case moreMenu, focusMenuRow, parentMenuRow, parentPicker, duplicateMenuRow
}
struct InspectorFramesKey: PreferenceKey {
    static let defaultValue: [InspectorRenderAnchor: CGRect] = [:]
    static func reduce(value: inout [InspectorRenderAnchor: CGRect],
                       nextValue: () -> [InspectorRenderAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
extension View {
    @ViewBuilder
    func inspectorRenderAnchor(_ anchor: InspectorRenderAnchor) -> some View {
        #if DEBUG
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: InspectorFramesKey.self,
                    value: [anchor: geometry.frame(in: .named("inspector-render"))])
            }
        }
        #else
        self
        #endif
    }
}
