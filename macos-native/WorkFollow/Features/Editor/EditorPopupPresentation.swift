import AppKit
import SwiftUI

struct EditorPopupTriggerFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

extension View {
    func editorPopupTriggerFrame(_ id: String) -> some View {
        background {
            #if DEBUG
            GeometryReader { geometry in
                Color.clear.preference(key: EditorPopupTriggerFramesKey.self,
                    value: [id: geometry.frame(in: .named(DocumentToolbarTooltip.space))])
            }
            #endif
        }
    }
}

/// Editor cards retain their own content widths while sharing safe edges and
/// caret placement. Dimensions here are presentation policy, not pixel parity.
enum EditorPopupGeometry {
    enum Side: Equatable { case above, below }
    enum Alignment: Equatable { case leading, trailing, center }

    static let gap: CGFloat = PopupMetrics.scheduleGap
    static let inset: CGFloat = PopupMetrics.screenInset

    static func frame(anchor: CGRect, size: CGSize, bounds: CGRect,
                      preferredSide: Side = .below,
                      alignment: Alignment = .leading,
                      gap: CGFloat = PopupMetrics.scheduleGap,
                      inset: CGFloat = PopupMetrics.screenInset) -> CGRect {
        let safe = bounds.insetBy(dx: min(inset, max(0, bounds.width / 2)),
                                  dy: min(inset, max(0, bounds.height / 2)))
        let width = min(max(0, size.width), max(0, safe.width))
        let desiredHeight = min(max(0, size.height), max(0, safe.height))
        let above = min(max(0, safe.maxY - anchor.maxY - gap), max(0, safe.height))
        let below = min(max(0, anchor.minY - safe.minY - gap), max(0, safe.height))
        let preferred = preferredSide == .above ? above : below
        let alternate = preferredSide == .above ? below : above
        let usePreferred = preferred >= desiredHeight || preferred >= alternate
        let side = usePreferred ? preferredSide : (preferredSide == .above ? .below : .above)
        let height = min(desiredHeight, usePreferred ? preferred : alternate)
        let rawX: CGFloat
        switch alignment {
        case .leading: rawX = anchor.minX
        case .trailing: rawX = anchor.maxX - width
        case .center: rawX = anchor.midX - width / 2
        }
        let rawY = side == .above ? anchor.maxY + gap : anchor.minY - gap - height
        return CGRect(x: min(max(rawX, safe.minX), safe.maxX - width),
                      y: min(max(rawY, safe.minY), safe.maxY - height),
                      width: width, height: height)
    }

    @MainActor
    static func bounds(in owner: NSWindow) -> CGRect {
        let content = owner.convertToScreen(owner.contentLayoutRect)
        return content.intersection(owner.screen?.visibleFrame ?? content)
    }

    @MainActor
    static func visibleFrame(of view: NSView) -> CGRect {
        guard let owner = view.window else { return .zero }
        return owner.convertToScreen(view.convert(view.bounds.intersection(view.visibleRect), to: nil))
    }

    static func tooltipX(anchor: CGRect, width: CGFloat, containerWidth: CGFloat) -> CGFloat {
        min(max(anchor.midX - width / 2, 0), max(0, containerWidth - width))
    }
}

/// Measures only the available size. AnchoredPropertyPanel still owns the
/// actual child window, outside-click routing, Escape and preserved focus.
struct EditorToolbarPopupCapacity: NSViewRepresentable {
    let anchor: CGRect
    let requestedSize: CGSize
    let onChange: (CGSize) -> Void

    final class Probe: NSView {
        override var isFlipped: Bool { true }
        var anchorRect = CGRect.zero
        var requestedSize = CGSize.zero
        var onChange: (CGSize) -> Void = { _ in }
        private var observers: [NSObjectProtocol] = []
        private var lastSize: CGSize?
        private var queued = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            if let owner = window {
                for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification,
                             NSWindow.didChangeScreenNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name,
                        object: owner, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.schedule() }
                    })
                }
            }
            schedule()
        }
        override func layout() { super.layout(); schedule() }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        func schedule() {
            guard !queued else { return }
            queued = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.queued = false
                guard let owner = self.window, !self.anchorRect.isEmpty else { return }
                let row = owner.convertToScreen(self.convert(self.anchorRect, to: nil))
                let size = EditorPopupGeometry.frame(anchor: row, size: self.requestedSize,
                    bounds: EditorPopupGeometry.bounds(in: owner), preferredSide: .above,
                    gap: PopupMetrics.controlGap).size
                guard size != self.lastSize else { return }
                self.lastSize = size
                self.onChange(size)
            }
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {
        view.anchorRect = anchor
        view.requestedSize = requestedSize
        view.onChange = onChange
        view.schedule()
    }
}

/// Child panels are ordered above their owner, but a child at the default level
/// can still fall behind a floating owner (the floating note). Raise only for
/// floating-or-higher hosts so normal windows keep their existing stacking.
enum EditorPopupWindowLevel {
    static func apply(to panel: NSPanel, owner: NSWindow) {
        guard owner.level.rawValue >= NSWindow.Level.floating.rawValue else { return }
        panel.level = NSWindow.Level(rawValue: owner.level.rawValue + 1)
    }
}

/// Completion panels only need passive geometry observation. Interaction and
/// keyboard commands remain with NativeTextView, so the editor stays focused.
final class EditorCompletionPanel: NSPanel {
    private var geometryObservers: [NSObjectProtocol] = []
    private weak var trackedOwner: NSWindow?
    private weak var trackedClip: NSClipView?
    private var reposition: (() -> Void)?
    private var queued = false

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func followGeometry(of editor: NSView, reposition: @escaping () -> Void) {
        self.reposition = reposition
        let clip = editor.enclosingScrollView?.contentView
        guard trackedOwner !== editor.window || trackedClip !== clip else { return }
        geometryObservers.forEach(NotificationCenter.default.removeObserver)
        geometryObservers.removeAll()
        trackedOwner = editor.window
        trackedClip = clip
        let moved: (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.queueReposition() }
        }
        if let owner = editor.window {
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification,
                         NSWindow.didChangeScreenNotification] {
                geometryObservers.append(NotificationCenter.default.addObserver(forName: name,
                    object: owner, queue: .main, using: moved))
            }
        }
        if let clip {
            clip.postsBoundsChangedNotifications = true
            geometryObservers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main, using: moved))
        }
    }

    private func queueReposition() {
        guard !queued else { return }
        queued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.queued = false
            self.reposition?()
        }
    }

    deinit { geometryObservers.forEach(NotificationCenter.default.removeObserver) }
}
