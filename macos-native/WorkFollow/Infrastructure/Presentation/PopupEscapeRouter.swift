import AppKit
import SwiftUI

/// Esc 的注册名次：同一个窗口里"更具体"的处理者先拿到 Esc。
///
/// 注意这个数字**不是层数**，而是同窗口内的竞争排序——子卡是独立 `NSPanel`，
/// 各自在自己的窗口注册，不参与父窗口的排名。以前这里散着裸数字（1 / 2 / 4），
/// 谁也说不清为什么是 4；现在改成有名字的名次。
enum PopupEscapeRank {
    /// 呈现壳自己的兜底关闭。
    static let shell = 1
    /// 嵌在壳里的面板（标签选择、属性面板等）。
    static let embedded = 2
    /// 日程面板的状态机：它知道"先弹哪一层"，必须压过壳的兜底关闭。
    static let schedule = 4
}

/// Presentation-only ownership. Mouse events are observed, never consumed.
/// A child taking key focus is still inside its owner's window family.
@MainActor
final class PopupInteractionRegistry {
    static let shared = PopupInteractionRegistry()
    private struct Entry {
        weak var window: NSWindow?
        let contains: (NSEvent) -> Bool
        let dismiss: () -> Void
    }
    private var entries: [UUID: Entry] = [:]
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    func register(window: NSWindow, contains: @escaping (NSEvent) -> Bool,
                  dismiss: @escaping () -> Void) -> UUID {
        let id = UUID()
        entries[id] = Entry(window: window, contains: contains, dismiss: dismiss)
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                self?.routeMouseDown(event) ?? event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                self?.dismissAll()
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                object: NSApp, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissAll() }
            })
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    self?.dismissOutsideFamily(of: notification.object as? NSWindow)
                }
            })
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: nil, queue: .main) { [weak self] _ in
                // Key transfer is not complete during didResignKey. Inspect the
                // resulting key window, not the transient nil between siblings.
                DispatchQueue.main.async { self?.dismissOutsideFamily(of: NSApp.keyWindow) }
            })
        }
        return id
    }

    func unregister(_ id: UUID) {
        entries.removeValue(forKey: id)
        guard entries.isEmpty else { return }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil; globalMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    func routeMouseDown(_ event: NSEvent) -> NSEvent {
        let outside = entries.values.filter { $0.window != nil && !$0.contains(event) }
        outside.forEach { $0.dismiss() }
        return event
    }

    func dismissAll() {
        let current = Array(entries.values)
        current.forEach { $0.dismiss() }
    }

    func dismissOutsideFamily(of keyWindow: NSWindow?) {
        func root(_ window: NSWindow) -> NSWindow {
            var result = window
            while let parent = result.parent { result = parent }
            return result
        }
        let outside = entries.values.filter { entry in
            guard let window = entry.window, let keyWindow else { return true }
            return root(window) !== root(keyWindow)
        }
        outside.forEach { $0.dismiss() }
    }
}

/// One event monitor, explicit window ownership, and deepest layer first.
/// This routes presentation only; drafts and commit decisions remain in the caller.
@MainActor
final class PopupEscapeRegistry {
    static let shared = PopupEscapeRegistry()
    private struct Entry {
        weak var view: NSView?
        let depth: Int
        let presentingWindow: () -> NSWindow?
        let action: () -> Void
    }
    private var entries: [(UUID, Entry)] = []
    private var monitor: Any?

    func register(view: NSView, depth: Int, presentingWindow: @escaping () -> NSWindow? = { nil }, action: @escaping () -> Void) -> UUID {
        let id = UUID()
        entries.append((id, Entry(view: view, depth: depth, presentingWindow: presentingWindow, action: action)))
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, self?.route(eventWindow: event.window) == true else { return event }
                return nil
            }
        }
        return id
    }

    func unregister(_ id: UUID) {
        entries.removeAll { $0.0 == id || $0.1.view == nil }
        if entries.isEmpty, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    @discardableResult
    func route(eventWindow: NSWindow?) -> Bool {
        guard let eventWindow, NSApp.modalWindow == nil,
              eventWindow.attachedSheet == nil else { return false }
        // A local event monitor runs before NSTextView.cancelOperation. Do not
        // close a child picker while its presenter input method owns Escape.
        if let input = eventWindow.firstResponder as? NSTextInputClient, input.hasMarkedText() {
            return false
        }
        let candidates = entries.enumerated().filter { _, pair in
            guard let view = pair.1.view, let owner = view.window,
                  owner.isVisible, owner.attachedSheet == nil,
                  !view.isHiddenOrHasHiddenAncestor else { return false }
            var ancestor: NSWindow? = owner
            while let window = ancestor {
                if eventWindow === window { return true }
                ancestor = window.parent
            }
            return eventWindow === pair.1.presentingWindow()
        }
        func windowDepth(_ view: NSView?) -> Int {
            var depth = 0
            var window = view?.window?.parent
            while let owner = window { depth += 1; window = owner.parent }
            return depth
        }
        let winner = candidates.max {
            let lhsWindowDepth = windowDepth($0.element.1.view)
            let rhsWindowDepth = windowDepth($1.element.1.view)
            if lhsWindowDepth != rhsWindowDepth { return lhsWindowDepth < rhsWindowDepth }
            return $0.element.1.depth == $1.element.1.depth
                ? $0.offset < $1.offset : $0.element.1.depth < $1.element.1.depth
        }
        guard let winner else { return false }
        winner.element.1.action()
        return true
    }
}

struct PopupEscapeRouter: NSViewRepresentable {
    @Environment(\.popupPresentingWindow) private var presentingWindow
    var depth = 1
    let onEscape: () -> Void
    final class Coordinator {
        var action: () -> Void
        var registration: UUID?
        init(action: @escaping () -> Void) { self.action = action }
    }
    func makeCoordinator() -> Coordinator { Coordinator(action: onEscape) }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        coordinator.registration = PopupEscapeRegistry.shared.register(view: view, depth: depth, presentingWindow: { [weak presentingWindow] in presentingWindow?.window }) { [weak coordinator] in
            coordinator?.action()
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.action = onEscape }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let id = coordinator.registration { PopupEscapeRegistry.shared.unregister(id) }
        coordinator.registration = nil
    }
}

/// A native Popover is not guaranteed to expose its presenter via NSWindow.parent.
/// Capture that relationship at the presentation boundary instead of guessing from keyWindow.
final class PopupPresentingWindow: ObservableObject {
    weak var window: NSWindow?
}

private struct PopupPresentingWindowKey: EnvironmentKey {
    static let defaultValue: PopupPresentingWindow? = nil
}

extension EnvironmentValues {
    var popupPresentingWindow: PopupPresentingWindow? {
        get { self[PopupPresentingWindowKey.self] }
        set { self[PopupPresentingWindowKey.self] = newValue }
    }
}

struct PopupPresentingWindowReader: NSViewRepresentable {
    let owner: PopupPresentingWindow
    final class Reader: NSView {
        weak var owner: PopupPresentingWindow?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            owner?.window = window
        }
    }
    func makeNSView(context: Context) -> Reader {
        let view = Reader()
        view.owner = owner
        return view
    }
    func updateNSView(_ nsView: Reader, context: Context) { owner.window = nsView.window }
}
