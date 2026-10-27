import AppKit
import Combine

@MainActor
enum NativeMainWindowPresenter {
    static func activate(reopen: (() -> Void)? = nil) {
        if let main = NSApp.windows.first(where: { $0.identifier?.rawValue == "WorkFollowNativeMain" }) {
            main.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else if let reopen {
            reopen()
        } else {
            // A widget-only launch may never have constructed the main scene.
            // A normal application reopen asks SwiftUI to present that scene.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.addsToRecentItems = false
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in }
        }
    }
}

@MainActor
final class WidgetMainWindowLaunchPolicy: ObservableObject {
    let startedForWidget: Bool
    let startedForAutomation: Bool
    @Published private(set) var suppressInitialMainWindow: Bool
    private var legacyWindows: [NSWindow] = []

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        startedForWidget = arguments.contains(WidgetQuickAddLaunch.argument)
        startedForAutomation = arguments.contains(AutomationChannel.launchArgument)
        suppressInitialMainWindow = startedForWidget || startedForAutomation
    }

    // macOS 14 has no Scene.defaultLaunchBehavior. Prepare its initial window
    // before display, then hide it when launching finishes. Later explicit
    // opens can use the same normal main window.
    func prepareLegacyMainWindow(_ window: NSWindow) {
        guard suppressInitialMainWindow, !legacyWindows.contains(where: { $0 === window }) else { return }
        window.alphaValue = 0
        legacyWindows.append(window)
    }

    func didFinishLaunching() {
        guard suppressInitialMainWindow else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for window in self.legacyWindows {
                window.orderOut(nil)
                window.alphaValue = 1
            }
            self.legacyWindows.removeAll()
            // Suppress only this initial launch. Dock/Finder reopen should
            // present the main scene normally after the quick card closes.
            self.suppressInitialMainWindow = false
        }
    }
}
