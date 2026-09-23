import AppKit
import SwiftUI

@main
struct WorkFollowApp: App {
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
