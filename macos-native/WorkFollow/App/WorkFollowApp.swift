import AppKit
import SwiftUI

@main
struct WorkFollowApp: App {
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(NativeLifecycleDelegate.self) private var lifecycle
    @StateObject private var environment: AppEnvironment
    @StateObject private var quickAdd: GlobalQuickAddController
    @StateObject private var statusItem: StatusItemController
    @State private var mainWindowRailInset: CGFloat = 0

    init() {
        let environment = AppEnvironment()
        let quickAdd = GlobalQuickAddController(workspace: environment.taskWorkspace)
        _environment = StateObject(wrappedValue: environment)
        _quickAdd = StateObject(wrappedValue: quickAdd)
        _statusItem = StateObject(wrappedValue: StatusItemController(quickAdd: quickAdd,
                                                                    focusStore: environment.focusStore,
                                                                    onOpenFocus: {
            environment.navigation.destination = .focus
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { !($0 is NSPanel) && $0.isVisible }?.makeKeyAndOrderFront(nil)
        }))
    }

    var body: some Scene {
        WindowGroup("WorkFollow Native", id: "main") {
            RootShellView(workspace: environment.taskWorkspace,
                          navigation: environment.navigation)
                .environmentObject(environment)
                .environment(\.mainWindowRailInset, mainWindowRailInset)
                .preferredColorScheme(environment.appearance.colorScheme)
                .tint(WFColors.accent)
                .frame(minWidth: WFMetrics.minimumWindow.width,
                       minHeight: WFMetrics.minimumWindow.height)
                .background(WindowFramePersistence())
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
        .commands { AppCommands(environment: environment, quickAdd: quickAdd) }

        Settings {
            SettingsShellView()
                .environmentObject(environment)
                .preferredColorScheme(environment.appearance.colorScheme)
                .tint(WFColors.accent)
        }
    }
}

@MainActor
final class NativeLifecycleDelegate: NSObject, NSApplicationDelegate {
    weak var environment: AppEnvironment?
    let resourceLinks = NativeResourceLinkReceiver()

    func application(_ application: NSApplication, open urls: [URL]) {
        resourceLinks.receive(urls)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let environment else { return .terminateNow }
        // End editing first so title fields and marked text reach the model.
        for window in sender.windows { window.makeFirstResponder(nil) }
        // 便签浮窗正文也走防抖,先冲刷再随 flush 落盘。
        StickyNoteWindowController.shared.closeAll()
        environment.flush { error in
            if let error {
                let alert = NSAlert()
                alert.messageText = "预览数据尚未保存"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "返回应用")
                alert.runModal()
            }
            sender.reply(toApplicationShouldTerminate: error == nil)
        }
        return .terminateLater
    }
}

/// Observe the host window without replacing SwiftUI's window delegate.
private struct WindowFramePersistence: NSViewRepresentable {
    func makeNSView(context: Context) -> FrameView { FrameView() }
    func updateNSView(_ nsView: FrameView, context: Context) {}

    final class FrameView: NSView {
        private var observers: [NSObjectProtocol] = []
        private weak var configuredWindow: NSWindow?
        private let frameName = "WorkFollowNativePreview.MainWindow"

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, configuredWindow !== window else { return }
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            configuredWindow = window
            window.identifier = NSUserInterfaceItemIdentifier("WorkFollowNativeMain")
            window.minSize = NSSize(width: WFMetrics.minimumWindow.width,
                                    height: WFMetrics.minimumWindow.height)
            window.setFrameUsingName(frameName)
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

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
