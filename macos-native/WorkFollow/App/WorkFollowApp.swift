import AppKit
import SwiftUI

@main
struct WorkFollowApp: App {
    @NSApplicationDelegateAdaptor(NativeLifecycleDelegate.self) private var lifecycle
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup("WorkFollow Native", id: "main") {
            RootShellView(workspace: environment.taskWorkspace,
                          navigation: environment.navigation)
                .environmentObject(environment)
                .preferredColorScheme(environment.appearance.colorScheme)
                .tint(WFColors.accent)
                .frame(minWidth: WFMetrics.minimumWindow.width,
                       minHeight: WFMetrics.minimumWindow.height)
                .background(WindowFramePersistence())
                .onAppear { lifecycle.environment = environment }
        }
        .defaultSize(width: WFMetrics.defaultWindow.width,
                     height: WFMetrics.defaultWindow.height)
        .windowResizability(.contentMinSize)
        .commands { AppCommands(environment: environment) }

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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let environment else { return .terminateNow }
        // End editing first so title fields and marked text reach the model.
        for window in sender.windows { window.makeFirstResponder(nil) }
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
