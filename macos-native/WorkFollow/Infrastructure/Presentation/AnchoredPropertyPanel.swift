import AppKit
import SwiftUI

#if DEBUG
/// Render tests observe preferences inside the real child host, not a replica
/// overlay in the owner. The transform is stable across host updates.
private struct PopupContentObservationKey: EnvironmentKey {
    static let defaultValue: ((AnyView) -> AnyView)? = nil
}
extension EnvironmentValues {
    var popupContentObservation: ((AnyView) -> AnyView)? {
        get { self[PopupContentObservationKey.self] }
        set { self[PopupContentObservationKey.self] = newValue }
    }
}
#endif

enum AnchoredPropertyPanelPlacement { case vertical, verticalInOwner, submenu, schedule, dropdown, cursor }

private struct PropertyPanelContentSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
enum AnchoredPropertyPanelFocusPolicy {
    case preservePresenter
    case panel
    /// Accept keyboard events without selecting a calendar tab or other control.
    case panelWindow
}

/// A child card has its own window: it can cross the parent's bottom edge without
/// contributing to the parent's fitting size. The row is the positioning anchor.
struct AnchoredPropertyPanel<PanelContent: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let width: CGFloat
    var horizontalOutset: CGFloat = 0
    var prefersAbove: Bool = false
    var placement: AnchoredPropertyPanelPlacement = .vertical
    var focusPolicy: AnchoredPropertyPanelFocusPolicy = .preservePresenter
    var title: String? = nil
    let content: () -> PanelContent

    final class AnchorView: NSView {
        var moved: (() -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); moved?() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    final class PropertyPanelWindow: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
        override func cancelOperation(_ sender: Any?) {
            if !PopupEscapeRegistry.shared.route(eventWindow: self) {
                super.cancelOperation(sender)
            }
        }
    }
    final class ContentHost: NSHostingView<AnyView> {
        var sizeInvalidated: (() -> Void)?
        override func invalidateIntrinsicContentSize() {
            super.invalidateIntrinsicContentSize()
            sizeInvalidated?()
        }
    }
    final class Coordinator {
        weak var anchor: AnchorView?
        var panel: NSPanel?
        var host: NSHostingView<AnyView>?
        var interactionRegistration: UUID?
        var ownerCloseObserver: NSObjectProtocol?
        var ownerVisibilityObserver: NSObjectProtocol?
        var ownerPopoverObserver: NSObjectProtocol?
        var dismiss: () -> Void = {}
        var width: CGFloat = 232
        var horizontalOutset: CGFloat = 0
        var prefersAbove = false
        var placement: AnchoredPropertyPanelPlacement = .vertical
        var focusPolicy: AnchoredPropertyPanelFocusPolicy = .preservePresenter
        var geometryObservers: [NSObjectProtocol] = []
        var root: AnyView = AnyView(EmptyView())
        var presented = false
        var escapeDepth = 3
        var presentingWindow: PopupPresentingWindow?
        var title: String?
        var popupFill: Color = WFColors.content
        private var lastContentSize: CGSize = .zero
        private var contentResizeQueued = false

        func update() {
            guard presented, let anchor, let owner = anchor.window, owner.isVisible else {
                close(); return
            }
            let card = root
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: PropertyPanelContentSizeKey.self, value: geometry.size)
                })
                .onPreferenceChange(PropertyPanelContentSizeKey.self) { [weak self] size in
                    self?.contentSizeChanged(size)
                }
                .background(popupFill, in: RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
                .clipShape(RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
                .background(PopupEscapeRouter(depth: escapeDepth) { [weak self] in self?.dismiss() })
                .environment(\.popupPresentingWindow, presentingWindow)
                .hidesSystemFocusEffect()
            if host == nil {
                let contentHost = ContentHost(rootView: AnyView(card))
                contentHost.sizeInvalidated = { [weak self] in self?.queueContentResize() }
                host = contentHost
                // The coordinator owns window geometry. Do not let SwiftUI's
                // min/max constraints resize NSPanel again after setFrame.
                host?.sizingOptions = [.intrinsicContentSize]
            }
            else { host?.rootView = AnyView(card) }
            guard let host else { return }
            let isOpening = panel == nil
            if isOpening {
                let window = PropertyPanelWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
                window.becomesKeyOnlyIfNeeded = true
                window.isReleasedWhenClosed = false
                window.title = title ?? (placement == .submenu ? "任务操作子菜单" : "日期属性")
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = true
                window.appearance = owner.effectiveAppearance
                window.contentView = host
                EditorPopupWindowLevel.apply(to: window, owner: owner)
                owner.addChildWindow(window, ordered: .above)
                panel = window
                for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                    geometryObservers.append(NotificationCenter.default.addObserver(forName: name, object: owner, queue: .main) { [weak self] _ in
                        DispatchQueue.main.async {
                            guard let self, self.presented else { return }
                            self.anchor?.window?.contentView?.layoutSubtreeIfNeeded()
                            self.update()
                        }
                    })
                }
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
                interactionRegistration = MainActor.assumeIsolated { PopupInteractionRegistry.shared.register(window: window, contains: { [weak self] event in
                    guard let self, let panel = self.panel, let parent = panel.parent else { return false }
                    // A descendant's event belongs to the child, not an outside
                    // click on its parent. Parent clicks close only the child.
                    var target = event.window
                    while let current = target {
                        if current === panel { return true }
                        target = current.parent
                    }
                    // The anchor row handles toggle/clear itself; don't cancel then reopen it.
                    if event.window === parent, let anchor = self.anchor, anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) {
                        return true
                    }
                    return false
                }, dismiss: { [weak self] in self?.dismiss() }) }
            }
            positionPanel(isOpening: isOpening)
        }

        private func contentSizeChanged(_ size: CGSize) {
            guard presented, size.height > 0, abs(size.height - lastContentSize.height) > 0.5 else { return }
            lastContentSize = size
            queueContentResize()
        }

        private func queueContentResize() {
            guard presented else { return }
            guard !contentResizeQueued else { return }
            contentResizeQueued = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.contentResizeQueued = false
                guard self.presented else { return }
                self.positionPanel(isOpening: false)
            }
        }

        private func positionPanel(isOpening: Bool) {
            guard let anchor, let owner = anchor.window, let host, panel != nil else { return }
            let screen = owner.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? owner.frame
            // Preferences describe the rendered content. AppKit's fittingSize
            // can still contain the previous intrinsic height during this turn.
            let intrinsicHeight = host.intrinsicContentSize.height
            let contentHeight = intrinsicHeight > 0 ? intrinsicHeight
                : lastContentSize.height > 0 ? lastContentSize.height : host.fittingSize.height
            let size = CGSize(width: width, height: min(contentHeight, screen.height - 2 * PopupMetrics.screenInset))
            let row = owner.convertToScreen(anchor.convert(anchor.bounds, to: nil))
                .insetBy(dx: -horizontalOutset, dy: 0)
            var rootOwner = owner
            while let parent = rootOwner.parent { rootOwner = parent }
            let frame: CGRect
            switch placement {
            case .submenu:
                frame = AnchoredPropertyPanelGeometry.submenuFrame(row: row, size: size, bounds: rootOwner.frame.intersection(screen))
            case .schedule:
                frame = AnchoredPropertyPanelGeometry.scheduleFrame(anchor: row, size: size, bounds: screen)
            case .dropdown:
                frame = AnchoredPropertyPanelGeometry.dropdownFrame(anchor: row, size: size, bounds: screen,
                                                                   prefersAbove: prefersAbove)
            case .cursor:
                frame = AnchoredPropertyPanelGeometry.frame(row: row, size: size, screen: screen, gap: 0)
            case .vertical:
                frame = AnchoredPropertyPanelGeometry.frame(row: row, size: size, screen: screen, prefersAbove: prefersAbove)
            case .verticalInOwner:
                frame = AnchoredPropertyPanelGeometry.frame(row: row, size: size,
                    screen: rootOwner.frame.intersection(screen), prefersAbove: prefersAbove)
            }
            panel?.setFrame(frame, display: true)
            if isOpening { panel?.orderFront(nil) }
            if isOpening, focusPolicy != .preservePresenter {
                panel?.makeKey()
                host.layoutSubtreeIfNeeded()
                if focusPolicy == .panelWindow {
                    panel?.makeFirstResponder(nil)
                } else {
                    panel?.recalculateKeyViewLoop()
                    if let input = firstEditableInput(in: host) {
                        panel?.makeFirstResponder(input)
                    } else {
                        panel?.selectNextKeyView(nil)
                    }
                }
            }
            panel?.invalidateShadow()
        }

        private func firstEditableInput(in view: NSView) -> NSView? {
            if let field = view as? NSTextField, field.isEditable, field.isEnabled {
                return field
            }
            for child in view.subviews {
                if let input = firstEditableInput(in: child) { return input }
            }
            return nil
        }

        func close() {
            lastContentSize = .zero
            contentResizeQueued = false
            geometryObservers.forEach(NotificationCenter.default.removeObserver)
            geometryObservers.removeAll()
            if let ownerCloseObserver { NotificationCenter.default.removeObserver(ownerCloseObserver) }
            ownerCloseObserver = nil
            if let ownerVisibilityObserver { NotificationCenter.default.removeObserver(ownerVisibilityObserver) }
            ownerVisibilityObserver = nil
            if let ownerPopoverObserver { NotificationCenter.default.removeObserver(ownerPopoverObserver) }
            ownerPopoverObserver = nil
            if let interactionRegistration {
                MainActor.assumeIsolated { PopupInteractionRegistry.shared.unregister(interactionRegistration) }
            }
            interactionRegistration = nil
            if let panel {
                // Return key ownership within the family before detaching a
                // focused child. Otherwise AppKit may choose an unrelated
                // window and the shared focus-loss observer closes the parent.
                if panel.isKeyWindow, NSApp.isActive,
                   let owner = panel.parent, owner.isVisible {
                    owner.makeKey()
                }
                panel.parent?.removeChildWindow(panel)
                panel.close()
            }
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
        coordinator.placement = placement
        coordinator.focusPolicy = focusPolicy
        coordinator.title = title
        coordinator.presentingWindow = context.environment.popupPresentingWindow
        coordinator.popupFill = context.environment.workfollowBackgroundTheme
            .popupFill(for: context.environment.colorScheme)
        // Closed anchors do not need to construct or retain panel content.
        if isPresented {
            coordinator.root = AnyView(content().environment(\.self, context.environment))
            #if DEBUG
            if let observe = context.environment.popupContentObservation {
                coordinator.root = observe(coordinator.root)
            }
            #endif
        } else {
            coordinator.root = AnyView(EmptyView())
        }
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
    /// Menu-like placement: align right edges and open below the value button.
    static func dropdownFrame(anchor: CGRect, size: CGSize, bounds: CGRect,
                              gap: CGFloat = PopupMetrics.controlGap,
                              prefersAbove: Bool = false) -> CGRect {
        let safe = bounds.insetBy(dx: PopupMetrics.screenInset, dy: PopupMetrics.screenInset)
        let width = min(size.width, safe.width), height = min(size.height, safe.height)
        let below = anchor.minY - gap - height
        let above = anchor.maxY + gap
        let proposedY = prefersAbove && above + height <= safe.maxY ? above
            : below >= safe.minY ? below
            : above + height <= safe.maxY ? above
            : max(safe.minY, min(below, safe.maxY - height))
        return CGRect(x: min(max(anchor.maxX - width, safe.minX), safe.maxX - width),
                      y: proposedY, width: width, height: height)
    }
    static func scheduleFrame(anchor: CGRect, size: CGSize, bounds: CGRect, gap: CGFloat = PopupMetrics.scheduleGap) -> CGRect {
        let safe = bounds.insetBy(dx: PopupMetrics.screenInset, dy: PopupMetrics.screenInset)
        let width = min(size.width, safe.width)
        let height = min(size.height, safe.height)
        let below = anchor.minY - gap - height
        let above = anchor.maxY + gap
        let proposedY: CGFloat
        if below >= safe.minY { proposedY = below }
        else if above + height <= safe.maxY { proposedY = above }
        else {
            let belowSpace = anchor.minY - gap - safe.minY
            let aboveSpace = safe.maxY - anchor.maxY - gap
            proposedY = belowSpace >= aboveSpace ? below : above
        }
        return CGRect(x: min(max(anchor.minX, safe.minX), safe.maxX - width),
                      y: min(max(proposedY, safe.minY), safe.maxY - height),
                      width: width, height: height)
    }
    static func submenuFrame(row: CGRect, size: CGSize, bounds: CGRect, gap: CGFloat = PopupMetrics.submenuGap) -> CGRect {
        let safe = bounds.insetBy(dx: PopupMetrics.screenInset, dy: PopupMetrics.screenInset)
        let width = min(size.width, safe.width)
        let height = min(size.height, safe.height)
        let right = row.maxX + gap
        let proposedX = right + width <= safe.maxX ? right : row.minX - gap - width
        return CGRect(x: min(max(proposedX, safe.minX), safe.maxX - width),
                      y: min(max(row.maxY - height, safe.minY), safe.maxY - height),
                      width: width, height: height)
    }
    static func frame(row: CGRect, size: CGSize, screen: CGRect, prefersAbove: Bool = false,
                      gap: CGFloat = PopupMetrics.controlGap) -> CGRect {
        let safe = screen.insetBy(dx: PopupMetrics.screenInset, dy: PopupMetrics.screenInset)
        let width = min(size.width, safe.width), height = min(size.height, safe.height)
        let below = row.minY - gap - height
        let above = row.maxY + gap
        let y = prefersAbove && above + height <= safe.maxY ? above
            : below >= safe.minY ? below : min(above, safe.maxY - height)
        return CGRect(x: min(max(row.minX, safe.minX), safe.maxX - width),
                      y: max(y, safe.minY), width: width, height: height)
    }
}
