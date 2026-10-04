import AppKit
import SwiftUI

enum MainWindowChromeGeometry {
    /// Keep the native control sizes. Only compact the gaps to fit the existing rail.
    static func trafficLightFrames(sizes: [CGSize], railWidth: CGFloat, top: CGFloat) -> [CGRect] {
        guard !sizes.isEmpty else { return [] }
        let total = sizes.reduce(CGFloat.zero) { $0 + $1.width }
        let margin: CGFloat = 3
        let gap = sizes.count > 1
            ? max(0, min(6, (railWidth - margin * 2 - total) / CGFloat(sizes.count - 1))) : 0
        var x = max(0, (railWidth - total - gap * CGFloat(sizes.count - 1)) / 2)
        return sizes.map { size in
            defer { x += size.width + gap }
            return CGRect(x: x, y: top, width: size.width, height: size.height)
        }
    }

    static func railInset(buttonFrames: [CGRect]) -> CGFloat {
        (buttonFrames.map(\.maxY).max() ?? 0) + (buttonFrames.isEmpty ? 0 : 8)
    }
}

/// Main-window-only chrome. Does not replace SwiftUI's window delegate or alter panels/settings.
struct MainWindowChromeConfiguration: NSViewRepresentable {
    @Binding var railInset: CGFloat

    static func configure(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        // Native titlebar retains dragging; editable content must not become a drag region.
        window.isMovableByWindowBackground = false
    }

    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        view.publishInset = { railInset = $0 }
        return view
    }

    func updateNSView(_ nsView: ChromeView, context: Context) {
        nsView.publishInset = { railInset = $0 }
    }

    final class ChromeView: NSView {
        var publishInset: ((CGFloat) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private weak var configuredWindow: NSWindow?
        private var updateScheduled = false
        private var lastInset: CGFloat?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            configuredWindow = window
            guard let window else { return }
            MainWindowChromeConfiguration.configure(window)
            for name in [NSWindow.didUpdateNotification, NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification,
                         NSWindow.didExitFullScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] _ in self?.scheduleUpdate() })
            }
            scheduleUpdate()
        }

        override func layout() {
            super.layout()
            scheduleUpdate()
        }

        private func scheduleUpdate() {
            guard !updateScheduled else { return }
            updateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateScheduled = false
                self.updateTrafficLights()
            }
        }

        private func updateTrafficLights() {
            guard let window = configuredWindow, let content = window.contentView else { return }
            guard !window.styleMask.contains(.fullScreen) else {
                publishIfChanged(0)
                return
            }
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
                .compactMap { window.standardWindowButton($0) }
            guard let container = buttons.first?.superview,
                  buttons.allSatisfy({ $0.superview === container }) else { return }
            let original = buttons.map { content.convert($0.bounds, from: $0) }
            let top = original.map { content.isFlipped ? $0.minY : content.bounds.height - $0.maxY }.min() ?? 0
            let targets = MainWindowChromeGeometry.trafficLightFrames(
                sizes: buttons.map { $0.frame.size }, railWidth: RailMetrics.width, top: top)
            for (button, rect) in zip(buttons, targets) {
                let contentRect = content.isFlipped ? rect : CGRect(
                    x: rect.minX, y: content.bounds.height - rect.maxY,
                    width: rect.width, height: rect.height)
                let frame = container.convert(contentRect, from: content)
                if button.frame != frame { button.frame = frame }
            }
            publishIfChanged(MainWindowChromeGeometry.railInset(buttonFrames: targets))
        }

        private func publishIfChanged(_ inset: CGFloat) {
            guard lastInset != inset else { return }
            lastInset = inset
            publishInset?(inset)
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
