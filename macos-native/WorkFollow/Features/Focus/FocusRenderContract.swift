import SwiftUI

/// Geometry reported only in Debug builds so render tests can verify real SwiftUI layout.
enum FocusRenderAnchor: Hashable {
    case rail
    case divider
    case timerRing
    case primaryButton
    case overviewFirstCard
    case recordsHeader

    static let coordinateSpaceName = "focus-render-contract"
}

struct FocusRenderFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [FocusRenderAnchor: CGRect] = [:]

    static func reduce(value: inout [FocusRenderAnchor: CGRect],
                       nextValue: () -> [FocusRenderAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    @ViewBuilder
    func focusRenderAnchor(_ anchor: FocusRenderAnchor) -> some View {
        #if DEBUG
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: FocusRenderFramesPreferenceKey.self,
                    value: [anchor: geometry.frame(in: .named(FocusRenderAnchor.coordinateSpaceName))]
                )
            }
        }
        #else
        self
        #endif
    }
}
