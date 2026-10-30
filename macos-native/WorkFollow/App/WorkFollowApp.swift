import AppKit
import SwiftUI

@main
struct WorkFollowApp: App {
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(NativeLifecycleDelegate.self) private var lifecycle
    @StateObject private var environment: AppEnvironment
    @StateObject private var quickAdd: GlobalQuickAddController
    @StateObject private var statusItem: StatusItemController
    @StateObject private var windowLaunch: WidgetMainWindowLaunchPolicy
    @State private var mainWindowRailInset: CGFloat = 0

    init() {
        let environment = AppEnvironment(layoutPreferences: .standard)
        environment.ensureWelcomeGuideIfNeeded()
        let windowLaunch = WidgetMainWindowLaunchPolicy()
        // 先把全部存储属性初始化完，才能碰 `self.`（属性包装器的 wrapped 访问
        // 也算 self 访问；lifecycle 的接线放在最后）。
        _windowLaunch = StateObject(wrappedValue: windowLaunch)
        _environment = StateObject(wrappedValue: environment)
        let quickAdd = GlobalQuickAddController(workspace: environment.taskWorkspace)
        _quickAdd = StateObject(wrappedValue: quickAdd)
        _statusItem = StateObject(wrappedValue: StatusItemController(quickAdd: quickAdd,
                                                                    focusStore: environment.focusStore,
                                                                    onOpenFocus: {
            environment.navigation.destination = .focus
            NativeMainWindowPresenter.activate()
        }))
        FloatingNoteWindowController.shared.attach(environment: environment)
        StickyNoteWindowController.shared.attach(environment: environment)
        lifecycle.windowLaunch = windowLaunch
        FocusPresentationWindows.attachAppearance(environment)
        FocusEndConfirmationPresenter.attach(to: environment.focusStore)
        lifecycle.environment = environment
        lifecycle.resourceLinks.configure(route: { [weak environment] url in
            environment?.openResourceLink(url) ?? false
        }, activate: { NativeMainWindowPresenter.activate() })
    }

    var body: some Scene {
        configuredMainWindow

        Settings {
            SettingsShellView()
                .environmentObject(environment)
                .preferredColorScheme(environment.appearance.colorScheme)
                .tint(WFColors.accent)
        }
        .handlesExternalEvents(matching: [])
    }

    private var configuredMainWindow: some Scene {
        // SceneBuilder has no if/else. Its public availability erasure keeps
        // both branches the same type without raising the macOS 14 minimum.
        if #available(macOS 15, *) {
            return SceneBuilder.buildOptional(SceneBuilder.buildLimitedAvailability(mainWindow
                .defaultLaunchBehavior(windowLaunch.suppressInitialMainWindow ? .suppressed : .automatic)
                .restorationBehavior(windowLaunch.startedForWidget || windowLaunch.startedForAutomation ? .disabled : .automatic)))
        }
        return SceneBuilder.buildOptional(SceneBuilder.buildLimitedAvailability(mainWindow))
    }

    private var mainWindow: some Scene {
        Window("WorkFollow Native", id: "main") {
            RootShellView(workspace: environment.taskWorkspace,
                          navigation: environment.navigation)
                .environmentObject(environment)
                .environment(\.mainWindowRailInset, mainWindowRailInset)
                .preferredColorScheme(environment.appearance.colorScheme)
                .tint(WFColors.accent)
                .frame(minWidth: WFMetrics.minimumWindow.width,
                       minHeight: WFMetrics.minimumWindow.height)
                .background(WindowFramePersistence(launchPolicy: windowLaunch))
                .background(MainWindowChromeConfiguration(railInset: $mainWindowRailInset))
                .onAppear {
                    lifecycle.environment = environment
                    lifecycle.resourceLinks.configure(route: { [weak environment] url in
                        environment?.openResourceLink(url) ?? false
                    }, activate: {
                        if let main = NSApp.windows.first(where: { $0.identifier?.rawValue == "WorkFollowNativeMain" }) {
                            main.makeKeyAndOrderFront(nil)
                        } else {
                            openWindow(id: "main")
                        }
                        NSApp.activate(ignoringOtherApps: true)
                    })
                }
        }
        .defaultSize(width: WFMetrics.defaultWindow.width,
                     height: WFMetrics.defaultWindow.height)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: [])
        .commands { AppCommands(environment: environment, quickAdd: quickAdd) }
    }
}

@MainActor
final class NativeLifecycleDelegate: NSObject, NSApplicationDelegate {
    weak var environment: AppEnvironment?
    weak var windowLaunch: WidgetMainWindowLaunchPolicy?
    let resourceLinks = NativeResourceLinkReceiver()

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowLaunch?.didFinishLaunching()
        _Concurrency.Task { await AIBackendBridge.shared.prewarm() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AIBackendBridge.shared.shutdown()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        resourceLinks.receive(urls)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let environment else { return .terminateNow }
        // End editing first so title fields and marked text reach the model.
        for window in sender.windows { window.makeFirstResponder(nil) }
        // 悬浮笔记和便签一样要先关窗（原生编辑器借 dismantle/flush 提交
        // 组合输入），再走统一 flush 落盘。
        FloatingEditorWindowController.shared.closeAll()
        environment.flush { error in
            if let error {
                WorkfollowDialog.notice("预览数据尚未保存", message: error.localizedDescription,
                                        button: "返回应用")
            }
            sender.reply(toApplicationShouldTerminate: error == nil)
        }
        return .terminateLater
    }
}

/// Observe the host window without replacing SwiftUI's window delegate.
private struct WindowFramePersistence: NSViewRepresentable {
    let launchPolicy: WidgetMainWindowLaunchPolicy
    func makeNSView(context: Context) -> FrameView {
        let view = FrameView()
        view.launchPolicy = launchPolicy
        return view
    }
    func updateNSView(_ nsView: FrameView, context: Context) {}

    final class FrameView: NSView {
        weak var launchPolicy: WidgetMainWindowLaunchPolicy?
        private var observers: [NSObjectProtocol] = []
        private var acceptanceMouseMonitor: Any?
        private weak var configuredWindow: NSWindow?
        private let frameName = "WorkFollowNativePreview.MainWindow"

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, configuredWindow !== window else { return }
            if #unavailable(macOS 15) { launchPolicy?.prepareLegacyMainWindow(window) }
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            if let acceptanceMouseMonitor { NSEvent.removeMonitor(acceptanceMouseMonitor) }
            acceptanceMouseMonitor = nil
            configuredWindow = window
            if NativeAcceptanceInteractionTrace.enabled {
                acceptanceMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak window] event in
                    MainActor.assumeIsolated {
                        if event.window === window {
                            NativeAcceptanceInteractionTrace.record(String(describing: event.type), [
                                "x": event.locationInWindow.x, "y": event.locationInWindow.y,
                                "active": NSApp.isActive, "keyWindow": window?.isKeyWindow ?? false
                            ])
                        }
                    }
                    return event
                }
            }
            window.identifier = NSUserInterfaceItemIdentifier("WorkFollowNativeMain")
            window.minSize = NSSize(width: WFMetrics.minimumWindow.width,
                                    height: WFMetrics.minimumWindow.height)
            if let size = NativeAcceptanceConfiguration.windowSize {
                let screen = (window.screen ?? NSScreen.main)?.visibleFrame
                let origin = screen.map { CGPoint(x: $0.minX, y: max($0.minY, $0.maxY - size.height)) }
                    ?? window.frame.origin
                window.setFrame(NSRect(origin: origin, size: size), display: false)
            } else {
                window.setFrameUsingName(frameName)
            }
            window.setFrameAutosaveName(frameName)
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self, weak window] _ in
                    guard let self, let window else { return }
                    window.saveFrame(usingName: self.frameName)
                })
            }
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
            if let acceptanceMouseMonitor { NSEvent.removeMonitor(acceptanceMouseMonitor) }
        }
    }
}
