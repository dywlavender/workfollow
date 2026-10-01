import AppKit
import SwiftUI

/// A child card has its own window: it can cross the parent's bottom edge without
/// contributing to the parent's fitting size. The row is the positioning anchor.
struct AnchoredPropertyPanel<PanelContent: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let width: CGFloat
    var horizontalOutset: CGFloat = 0
    var prefersAbove: Bool = false
    let content: () -> PanelContent

    final class AnchorView: NSView {
        var moved: (() -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); moved?() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    final class PropertyPanelWindow: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
    final class Coordinator {
        weak var anchor: AnchorView?
        var panel: NSPanel?
        var host: NSHostingView<AnyView>?
        var monitor: Any?
        var ownerCloseObserver: NSObjectProtocol?
        var ownerVisibilityObserver: NSObjectProtocol?
        var ownerPopoverObserver: NSObjectProtocol?
        var dismiss: () -> Void = {}
        var width: CGFloat = 232
        var horizontalOutset: CGFloat = 0
        var prefersAbove = false
        var root: AnyView = AnyView(EmptyView())
        var presented = false

        func update() {
            guard presented, let anchor, let owner = anchor.window, owner.isVisible else {
                close(); return
            }
            let card = root
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .background(WFColors.content, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .background(PopupEscapeRouter(depth: 3) { [weak self] in self?.dismiss() })
            if host == nil { host = NSHostingView(rootView: AnyView(card)) }
            else { host?.rootView = AnyView(card) }
            guard let host else { return }
            if panel == nil {
                let window = PropertyPanelWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
                window.becomesKeyOnlyIfNeeded = true
                window.isReleasedWhenClosed = false
                window.title = "日期属性"
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = true
                window.contentView = host
                owner.addChildWindow(window, ordered: .above)
                panel = window
                ownerCloseObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification, object: owner, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.presented = false
                        self?.dismiss()
                        self?.close()
                    }
                }
                ownerVisibilityObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification, object: owner, queue: .main
                ) { [weak self, weak owner] _ in
                    MainActor.assumeIsolated {
                        guard owner?.isVisible != true else { return }
                        self?.presented = false
                        self?.dismiss()
                        self?.close()
                    }
                }
                // NSPopover caches its window after close; window-close alone is insufficient.
                ownerPopoverObserver = NotificationCenter.default.addObserver(
                    forName: NSPopover.willCloseNotification, object: nil, queue: .main
                ) { [weak self, weak owner] notification in
                    MainActor.assumeIsolated {
                        guard let popover = notification.object as? NSPopover,
                              let owner,
                              popover.contentViewController?.view.window === owner else { return }
                        self?.presented = false
                        self?.dismiss()
                        self?.close()
                    }
                }
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    guard let self, let panel = self.panel, let parent = panel.parent else { return event }
                    if event.window === panel { return event }
                    guard event.window === parent else { return event }
                    // The anchor row handles toggle/clear itself; don't cancel then reopen it.
                    if let anchor = self.anchor, anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) {
                        return event
                    }
                    self.dismiss()
                    return event
                }
            }
            let screen = owner.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? owner.frame
            let size = CGSize(width: width, height: min(host.fittingSize.height, screen.height - 16))
            let row = owner.convertToScreen(anchor.convert(anchor.bounds, to: nil))
                .insetBy(dx: -horizontalOutset, dy: 0)
            let frame = AnchoredPropertyPanelGeometry.frame(row: row, size: size, screen: screen, prefersAbove: prefersAbove)
            panel?.setFrame(frame, display: true)
            panel?.orderFront(nil)
            panel?.invalidateShadow()
        }

        func close() {
            if let ownerCloseObserver { NotificationCenter.default.removeObserver(ownerCloseObserver) }
            ownerCloseObserver = nil
            if let ownerVisibilityObserver { NotificationCenter.default.removeObserver(ownerVisibilityObserver) }
            ownerVisibilityObserver = nil
            if let ownerPopoverObserver { NotificationCenter.default.removeObserver(ownerPopoverObserver) }
            ownerPopoverObserver = nil
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if let panel { panel.parent?.removeChildWindow(panel); panel.close() }
            panel = nil; host = nil
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        context.coordinator.anchor = view
        view.moved = { [weak coordinator = context.coordinator] in
            DispatchQueue.main.async { coordinator?.update() }
        }
        return view
    }
    func updateNSView(_ nsView: AnchorView, context: Context) {
        let coordinator = context.coordinator
        coordinator.presented = isPresented
        coordinator.width = width
        coordinator.horizontalOutset = horizontalOutset
        coordinator.prefersAbove = prefersAbove
        coordinator.root = AnyView(content().environment(\.self, context.environment))
        coordinator.dismiss = { isPresented = false }
        DispatchQueue.main.async { [weak coordinator] in coordinator?.update() }
    }
    static func dismantleNSView(_ nsView: AnchorView, coordinator: Coordinator) {
        nsView.moved = nil
        coordinator.presented = false
        coordinator.close()
    }
}

enum AnchoredPropertyPanelGeometry {
    static func frame(row: CGRect, size: CGSize, screen: CGRect, prefersAbove: Bool = false) -> CGRect {
        let x = min(max(row.minX, screen.minX + 8), screen.maxX - size.width - 8)
        let below = row.minY - size.height
        let above = row.maxY
        let y = prefersAbove && above + size.height <= screen.maxY - 8 ? above
            : below >= screen.minY + 8 ? below : min(above, screen.maxY - size.height - 8)
        return CGRect(x: x, y: max(y, screen.minY + 8), width: size.width, height: size.height)
    }
}
