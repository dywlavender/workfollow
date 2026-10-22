import SwiftUI

private struct PropertyPanelAnchors<Trigger: Hashable>: PreferenceKey {
    static var defaultValue: [Trigger: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [Trigger: Anchor<CGRect>],
                       nextValue: () -> [Trigger: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    /// Container hosts mark the actual button rather than using the whole header.
    func propertyPanelTrigger<Trigger: Hashable>(_ trigger: Trigger) -> some View {
        anchorPreference(key: PropertyPanelAnchors<Trigger>.self, value: .bounds) { [trigger: $0] }
    }

    func anchoredPropertyPanel<Trigger: Hashable, Panel: View>(
        isPresented: Binding<Bool>, trigger: Trigger, width: CGFloat,
        placement: AnchoredPropertyPanelPlacement = .dropdown,
        focusPolicy: AnchoredPropertyPanelFocusPolicy = .preservePresenter,
        title: String,
        @ViewBuilder panel: @escaping () -> Panel
    ) -> some View {
        overlayPreferenceValue(PropertyPanelAnchors<Trigger>.self) { anchors in
            if isPresented.wrappedValue, let anchor = anchors[trigger] {
                GeometryReader { geometry in
                    let rect = geometry[anchor]
                    AnchoredPropertyPanel(isPresented: isPresented, width: width,
                                          placement: placement, focusPolicy: focusPolicy, title: title,
                                          content: panel)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
                .allowsHitTesting(false)
            }
        }
    }
}
