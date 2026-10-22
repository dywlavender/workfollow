import AppKit
import SwiftUI

extension View {
    func businessContextMenu<Content: View>(width: CGFloat = PopupMetrics.menuWidth,
                                           @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(BusinessContextMenuModifier(width: width, menu: content))
    }
}

private struct BusinessContextMenuModifier<Menu: View>: ViewModifier {
    let width: CGFloat
    @ViewBuilder let menu: () -> Menu
    @State private var presented = false
    @State private var point = CGPoint.zero
    @StateObject private var controller = BusinessMenuController()

    func body(content: Content) -> some View {
        content
            .background(BusinessContextMenuTrigger { position in point = position; controller.reset(); presented = true })
            .overlay(alignment: .topLeading) {
                if presented {
                    AnchoredPropertyPanel(isPresented: $presented, width: width,
                        placement: .cursor, focusPolicy: .preservePresenter, title: "操作菜单") {
                        BusinessMenuContent(controller: controller, close: { presented = false },
                            dismissAll: { presented = false }, content: menu)
                    }
                    .frame(width: 1, height: 1).offset(x: point.x, y: point.y)
                    .allowsHitTesting(false)
                }
            }
            .onDisappear { presented = false; controller.reset() }
    }
}

private struct BusinessContextMenuTrigger: NSViewRepresentable {
    let show: (CGPoint) -> Void
    final class TargetView: NSView {
        var registration: UUID?
        var show: (CGPoint) -> Void = { _ in }
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> TargetView {
        let view = TargetView()
        view.registration = PopupInteractionRegistry.shared.registerContext(view: view) { [weak view] in view?.show($0) }
        return view
    }
    func updateNSView(_ view: TargetView, context: Context) { view.show = show }
    static func dismantleNSView(_ view: TargetView, coordinator: ()) {
        if let registration = view.registration { PopupInteractionRegistry.shared.unregisterContext(registration) }
    }
}
